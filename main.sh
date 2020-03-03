#!/bin/bash
#
# Main Script for Assembling & Preprocessing NICAP dataset
#
# TODO Option Parsing
# TODO Control Flow
# TODO stderr/out logging
# TODO check for SGE
#
############################################################################################################################################
# --------------------------------------------> 																					Defaults 
############################################################################################################################################
## Default Variables are set in this function
function declare_defaults(){
	# User Configurable Defaults
	[ ! "${BIDSDIR}" ] && BIDSDIR=${HOME}/nicap
	[ ! "${WORKDIR}" ] && WORKDIR=/Volumes/Anvil/sync/furnace/nicap
	[ ! "${SOURCEDATA}" ] && SOURCEDATA=${BIDSDIR}/bids
	[ ! "${DATAMANIFEST}" ] && DATAMANIFEST="${BIDSDIR}/docs/data-manifest.txt"
	[ ! "${MASTERCOV}" ] && MASTERCOV=${BIDSDIR}/docs/sociobeh-data.txt
	[ ! "${SSTCOV}" ] && SSTCOV=${BIDSDIR}/docs/nicap55_sociobeh-data.txt
	[ ! "${SSTNAME}" ] && SSTNAME=$(echo ${SSTCOV} | sed 's|/| |g' | awk '{print $NF}' | sed 's|_| |g' | awk '{print $1}')
	[ ! "${SST}" ] && SST=${WORKDIR}/sst/${SSTNAME}.nii.gz	
	[ ! "${SSTINIT}" ] && SSTINIT=${BIDSDIR}/external/ads56_sst/templates/ads56.nii.gz
	[ ! "${MNITEMPLATE}" ] && MNITEMPLATE=${BIDSDIR}/external/MNI152/MNI152_T1_1mm.nii.gz
	[ ! "${SUBJECTS}" ] && SUBJECTS=$(tail -n +2 ${MASTERCOV} | awk '{printf "%04s\n", $1}' | sort -u)
	[ ! "${PARALLELOPT}" ] && PARALLELOPT=''
	[ ! "${OVERWRITE}" ] && OVERWRITE=''
	[ ! "${QUEUE}" ] && QUEUE='main'
	[ ! "${STDERRLOG}" ] && STDERRLOG=/dev/null
	# Preset Directories
	T1WDIR=${BIDSDIR}/derivatives/t1w
	RESTDIR=${BIDSDIR}/derivatives/bold/rest
	# Static Variables
	ACQS=('dwi_dir-blipdown' 'dwi_dir-blipup' 'func_dir-blipdown' 'func_dir-blipup' 'B1000' 'B2000' 'B2800')
	[ ! "${MODALITY_STRUCT}" ] && MODALITY_STRUCT=('T1w' 'T2w')
	[ ! "${MODALITY_BOLD}" ] && MODALITY_BOLD=('bold')
	[ ! "${MODALITY_DWI}" ] && MODALITY_DWI=('dwi')
	[ ! "${MODALITY_FMAP}" ] && MODALITY_FMAP=('epi' 'sbref')
	MODS=(${MODALITY_STRUCT[@]} ${MODALITY_BOLD[@]} ${MODALITY_DWI[@]} ${MODALITY_FMAP[@]})
	TASKS=('rest')
	# default SST parameters
	[ ! "${SST_SHRINKFACTOR}" ] && SST_SHRINKFACTOR='10x8x6x4x2x1'
	[ ! "${SST_SMOOTH}" ] && SST_SMOOTH='6x4x2x1x1x0'
	[ ! "${SST_NUMQITER}" ] && SST_NUMQITER='100x100x100x70x70x30'	
	# use appropriate similarity metric - Mutual Information works best for multicontrast images
	if [ ${#MODALITY_STRUCT[@]} -gt 1 ]; then
		SST_SIMILARITYMETRIC='MI'
	else
		SST_SIMILARITYMETRIC='CC'
	fi		
	# static parameters
	export RED='\033[0;31m'
	export BRED='\033[1;31m'
	export YELLOW='\033[1;33m'
	export GREEN='\033[1;32m'
	export BLUE='\033[1;34m'
	export GREY='\033[1;37m'
	export NC='\033[0m' 
	export BBLUE='\033[1;40m'
	export NBC='\033[49m'
	export GGREY='\033[1;30m'
	export YBC='\033[47m'
	export LRED='\033[1;31m'	
	LOG="/tmp/main.runtime.$$"
	export LOGOUT=${LOG}.out && export LOGERR=${LOG}.err
}
export -f declare_defaults
############################################################################################################################################
# --------------------------------------------> 																				Check | Main
############################################################################################################################################
## This function checks for directory + software existence necessary to run software
##
# TODO add check for jq
function check(){
	# check for directories
	if [ ! -d ${BIDSDIR} ]; then
		echo -e "${BRED}\nERROR: ${BIDSDIR} not found" >&2
		EXITSTATUS=1
	fi
	# check for directories
	if [ ! -d ${BIDSDIR} ]; then
		echo -e "${BRED}\nERROR: ${BIDSDIR}/bids not found" >&2
		EXITSTATUS=1
	fi
	# check for directories
	if [ ! -d ${BIDSDIR} ]; then
		echo -e "${BRED}\nERROR: ${BIDSDIR}/sourcedata not found" >&2
		EXITSTATUS=1
	fi			
	if [ ! -d ${T1WDIR} ]; then
		echo -e "${BRED}\nERROR: ${T1WDIR} not found" >&2
		EXITSTATUS=1
	fi
	# check for required files
	if [ ! -f ${MASTERCOV} ]; then
		echo -e "${BRED}\nERROR: ${MASTERCOV} not found" >&2
		EXITSTATUS=1
	fi
	# TODO check for existence of SSTCOV
	#	
	# check for software?
	# - GNU parallel
	if [ ! $(command -v parallel) ]; then
		echo -e "${BRED}\nERROR: GNU Parallel not found, please install GNU Parallel" >&2
		EXITSTATUS=1
	fi	
	# - JSON parser
	if [ ! $(command -v qp) ]; then
		echo -e "${BRED}\nERROR: qp, please install qp" >&2
		EXITSTATUS=1
	fi		
	# - TODO AFNI
	# - ANTs
	if [ ! -d ${ANTSPATH} ]; then
		echo -e "${BRED}\nERROR: ${ANTSPATH} not found, please install ANTs" >&2
		EXITSTATUS=1
	fi
	# - TODO MRIQC
	# - TODO FreeSurfer
	# - TODO FSL
	# - TODO SGE
	# - TODO check servers in parallel opts
	# - TODO check outputs for processing pipelines
	#	-- denoised, brainmasks, segmentations, sst
	##
	# manifest check
	check_manifest
	#
	# - retrieve best runs
	# BESTRUNS=$(tail -n +2 ${MASTERCOV} | awk '{ printf "sub-%03s_ses-00%s_%s best-%s\n", $2,$3,$5,$7}' | grep 'best-1' | awk '{print $1}')
	# echo "${BESTRUNS}" > ${WORKDIR}/best-run-list.txt	
}
export -f check
############################################################################################################################################
# --------------------------------------------> 																			  Check | NIFTIs
############################################################################################################################################
## Generate File Manifest
## This function loops through all subjects within the master dataframe and pulls all associated NIFTI data. Each
## NIFTI is queried for basic parameters (x,y,z,t dimensions + phase encoding direction & echo spacing). You
## can use this manifest to quickly obtain lists of files with specific parameters of acquisitions.
##
function check_manifest(){
	TABLE='' 
	# Table Header
	header="subjectID\twave\trun\ttask\tacq\tmodality\tphase-enc-dir\ttot-read-time\teff-echo-spacing\txdim\tydim\tzdim\ttdim\txres\tyres\tzres\ttres\n"
	TABLE+=$(echo ${header})
	# loop across all subjects in dataset
	for subject in ${SUBJECTS}; do
		SUBID=$(echo "sub-${subject}")
		files=$(find ${BIDSDIR}/bids/${SUBID} -name '*.nii.gz')
		# loop across all files found for subject
		for f in ${files}; do
			RUNID=''
			SESID=$(echo ${f} | grep -oE 'ses-wave[1-3]' | sort -u)
			RUNID=$(echo ${f} | grep -oE 'run-0[1-9]' | sed 's|-| |g' | awk '{print $NF}' | sed 's|0||g')
			[ ! ${RUNID} ] && RUNID='1'
			# identify modality label
			for mod in ${MODS[@]}; do
				if echo ${f} | grep ${mod} > /dev/null; then
					MOD=${mod}
				else
					mod=''
				fi				
				# identify acq label
				if echo ${f} | grep 'acq' > /dev/null; then
					for acq in ${ACQS[@]}; do
						if echo ${f} | grep ${acq} > /dev/null; then
							ACQ=${acq}
						fi
					done
				else
					ACQ='NA';
				fi				
				# identify task label
				if echo ${f} | grep 'task' > /dev/null; then
					for task in ${TASKS[@]}; do
						if echo ${f} | grep ${task} > /dev/null; then
							TASK=${task}
						fi
					done
				else
					TASK='NA'
				fi					
			done
			# set dimenions to missing by default
			XDIM='NA'
			YDIM='NA'
			ZDIM='NA'
			TDIM='NA'
			XRES='NA'
			YRES='NA'
			ZRES='NA'
			TRES='NA'
			# now check if file has dimensions
			# TODO move away from FSL
			XDIM=$(fslinfo ${f} | grep -w 'dim1' | awk '{print $NF}')
			YDIM=$(fslinfo ${f} | grep -w 'dim2' | awk '{print $NF}') 
			ZDIM=$(fslinfo ${f} | grep -w 'dim3' | awk '{print $NF}')
			TDIM=$(fslinfo ${f} | grep -w 'dim4' | awk '{print $NF}')
			XRES=$(fslinfo ${f} | grep -w 'pixdim1' | awk '{print $NF}')
			YRES=$(fslinfo ${f} | grep -w 'pixdim2' | awk '{print $NF}')
			ZRES=$(fslinfo ${f} | grep -w 'pixdim3' | awk '{print $NF}')
			TRES=$(fslinfo ${f} | grep -w 'pixdim4' | awk '{print $NF}')
			# now check phase encoding direction
			PED=$(jq '.PhaseEncodingDirection' $(echo ${f} | sed 's|.nii.gz|.json|g'))
			# now check phase encoding direction
			ES=$(jq '.EffectiveEchoSpacing' $(echo ${f} | sed 's|.nii.gz|.json|g'))	
			# now check total readout time
			TotRT=$(jq '.TotalReadoutTime' $(echo ${f} | sed 's|.nii.gz|.json|g'))	
			[ ${PED} == 'null' ] && PED='NA'
			[ ${ES} == 'null' ] && ES='NA'
			[ ${TotRT} == 'null' ] && TotRT='NA'
			# specify as missing data if modality not found in string
			[ ! ${MOD} ] && MOD='NA'
			# add to table
			echo -e "${SUBID}\t${SESID}\t${RUNID}\t${TASK}\t${ACQ}\t${MOD}\t${PED}\t${TotRT}\t${ES}\t${XDIM}\t${YDIM}\t${ZDIM}\t${TDIM}\t${XRES}\t${YRES}\t${ZRES}\t${TRES}\n"
			TABLE+=$(echo "${SUBID}\t${SESID}\t${RUNID}\t${TASK}\t${ACQ}\t${MOD}\t${PED}\t${TotRT}\t${ES}\t${XDIM}\t${YDIM}\t${ZDIM}\t${TDIM}\t${XRES}\t${YRES}\t${ZRES}\t${TRES}\n")
		done
	done
	echo -e "${TABLE}" > ${DATAMANIFEST}
}
export -f check_manifest
############################################################################################################################################
# --------------------------------------------> 																	   Check | NIFTIs | JSON
############################################################################################################################################
# todo parse bids dir and create JSON with concatenated objects
#	   fields:
#			   - subject
#					-- demographic data
#					-- session
#						-- mri
#				  			* anat
#								- array of runs
#								- for each run:
# 									-- x,y,z,t dimensions, all params 
#									-- best run
#									-- qc metrics (mriqc/manual qc)
#							* func
#							* dwi
#							* fmap?
#						-- behavior 
#						-- physio
#
# todo list of files / patterns to check for dataset
# todo doi
# todo link
function check_manifest_json(){
	# initialize bids config json here
	local dir=${1} && shift
	local dir_size="$(du -d 1 -c -h ${dir} | grep 'total' | awk '{print $1}')"
	# find all subjects with json
	local num_subjects=$(find "${dir}"/ -name '*.json' -type f | wc -l)
	dataset_config="${dir}"/dataset_recons_config.json
	############################################################################################
	# Create JSON template
	############################################################################################
	jq -n '{Description: "FreeSurfer Subjects Directory Metadata", "SubjectsDirectory":"'"$subjects_dir}"'", "SubjectsDirectorySize":"'${subjects_dir_size}'", "SubjectsDirectoryNumber":"'${subjects_dir_num}'", Subjects: []}' > "${dataset_config}"

}
function check_manifest_subject(){
	# populate data for each subject here
	echo wip
}
############################################################################################################################################
# --------------------------------------------> 													            Check | FreeSurfer | Subject
############################################################################################################################################
## 
function check_freesurfer_subject(){
	local subject=${1} && shift
	local subjects_dir=${1} && shift
	############################
	## json defaults
	############################
	local status='null'	
	local runstatus='null'
	local starttime='null'	
	local runtime='null'
	local finishtime='null'
	local runid='null'
	local host='null'
	local failpoint='null'
	local failtime='null'
	####################################################################################################################	
	local recon="${subjects_dir}"/"${subject}/scripts/recon-all.log"	
	local config="${subjects_dir}"/config.json
	[ ! -f "${config}" ] && check_freesurfer_json "${subjects_dir}"
	####################################################################################################################	
	# check if subjects directory exists
	####################################################################################################################	
	if [ ! -d "${subjects_dir}"/"${subject}" ]; then
		printf "%s\033[K${YELLOW}◀︎|⁃‣Missing FreeSurfer Subjects Directory :: ${NC}%s" "${subjects_dir}"/"${subject}"
		status='no-data'
	fi
	####################################################################################################################	
	# check for recon-all log
	####################################################################################################################	
	if [ ! -f "${recon}" ]; then 
		printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC}Missing Recon All Log :: ${NC}%s" "${subjects_dir}"/"${subject}"/scripts
		status='missing-recon-log'
	fi
	####################################################################################################################	
	# Look for Active Jobs
	####################################################################################################################	
	if find "${subjects_dir}/${subject}" \( ! -regex '.*/\..*' \) -name 'IsRunning*'; then
		status='active-job-running'
		runstatus="$(tail -n 1 "${subjects_dir}/${subject}/scripts/recon-all-status.log" | sed "s|#@#|⦿|g" | awk '{i = 6; for (--i; i>=0; i--){$(NF-i)=""}print}'| awk '{{$NF=""}print}')"
		runtime="$(grep -oE '[A-Z][a-z]{1,2}.[A-Z][a-z]{1,2}.{1,2}[1-9]{1,2}.{1,2}[0-2][0-9]:[0-9][0-9]:[0-9][0-9].[A-Z]{1,3}.[0-9]{2,4}' "${recon}" | tail -n 1)"
		runid="$(grep "PROCESSID" "${subjects_dir}/${subject}/scripts/IsRunning*" | awk '{print $NF}')"
		host="$(grep "HOST" "${subjects_dir}/${subject}/scripts/IsRunning*" | awk '{print $NF}' | sed 's/.local//')"
	####################################################################################################################	
	# Look for Successfully Completed Jobs
	####################################################################################################################		
	elif tail -n 5 "${recon}" | grep -B 0 "finished without error"; then
		status='completed-job-without-error'
		starttime="$(tail -n 5 ${recon} | grep -B 0 "Started at" | head -n 1 | sed 's/Started at //g')"
		finishtime="$(tail -n 5 ${recon} | grep -B 0 "finished without error" | sed 's|\\n| |g' | egrep -o '[A-Z][a-z]{1,2}.[A-Z][a-z]{1,2}.{1,2}[1-9]{1,2}.{1,2}[0-2][0-9]:[0-9][0-9]:[0-9][0-9].[A-Z]{1,3}.[0-9]{2,4}' | tail -n 1)"
		host="$(grep "hostname" ${recon} | tail -n 1 | awk '{print $NF}' | sed 's/.local//')"
	####################################################################################################################	
	# Look for Failed Jobs
	####################################################################################################################		
	elif tail -n 10 "${recon}" | grep -B 0 "exited with ERRORS at"; then
		status='failed-job'
		failpoint="$(tail -n 5 "${subjects_dir}/${subject}/scripts/recon-all-status.log" | grep '#@#' | tail -n 1 | sed "s|#@#|⦿|g" | awk '{i = 6; for (--i; i>=0; i--){$(NF-i)=""}print}'| awk '{{$NF=""}print}')"
		failtime="$(tail -n 5 ${recon} | grep -B 0 "exited with ERRORS at" | egrep -o '[A-Z][a-z]{1,2}.[A-Z][a-z]{1,2}.{1,2}[1-9]{1,2}.{1,2}[0-2][0-9]:[0-9][0-9]:[0-9][0-9].[A-Z]{1,3}.[0-9]{2,4}' | tail -n 1)"
		host="$(grep 'hostname' ${recon} | tail -1 | awk '{print $NF}' | sed 's/.local//')"
	####################################################################################################################
	# Look for Other Jobs
	####################################################################################################################
	else
		status='unknown-status'
		failpoint="$(tail -n 5 "${subjects_dir}/${subject}/scripts/recon-all-status.log" | grep '#@#' | tail -n 1 | sed "s|#@#|⦿|g" | awk '{i = 6; for (--i; i>=0; i--){$(NF-i)=""}print}'| awk '{{$NF=""}print}')"
		failtime="$(tail -n 5 ${recon} | grep -B 0 "exited with ERRORS at" | egrep -o '[A-Z][a-z]{1,2}.[A-Z][a-z]{1,2}.{1,2}[1-9]{1,2}.{1,2}[0-2][0-9]:[0-9][0-9]:[0-9][0-9].[A-Z]{1,3}.[0-9]{2,4}' | tail -n 1)"
		host="$(grep 'hostname' ${recon} | tail -1 | awk '{print $NF}' | sed 's/.local//')"		
	fi
	####################################################################################################################
	# Check File Manifest
	####################################################################################################################
	export manifest=$(cat ${BIDSDIR}/docs/fs-files-manifest.txt)
	if check_freesurfer_suject_manifest "${subject}" "${subjects_dir}" "${manifest}"; then
		printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} check_freesurfer_suject_manifest ${subject} ${subjects_dir} ${manifest}"
	else
		printf "\r\033[K${BRED}◀︎|⁃‣SUCCESS${NC} check_freesurfer_suject_manifest ${subject} ${subjects_dir} ${manifest}"
	fi
	####################################################################################################################
	# Update JSON Configuration FIle
	####################################################################################################################
		jq -n '{Subject: {name: "'${SUBJECT}'", sex:"'${SUBJECT_SEX}'", Sessions:[]}}' > "${subject_config}"
		jq '.Subjects += [{"'${SUBJECT}'":{}}]' "${dataset_config}" > "${tmpfile}"
		jq '.' "${tmpfile}" > "${dataset_config}"	
	jq '.Subjects.'"${subject}"' = {status: '"${status}"', complete_manifest: '"${COMPLETESUB}"', needs_rerun:'"${RERUNSUB}"', runid: '"${runid}"', hostname: '"${host}"', run_status: '"${runstatus}"', start_time: '"${starttime}"', run_time: '"${runtime}"', fail_time: '"${failtime}"', total_run_time: '"${finishtime}"', failpoint: '"${failpoint}"', existing_files: '"${EXISTS[*]}"', missing_files: '"${MISSING[*]}"'' "${subjects_dir}"/config.json > "${subjects_dir}"/tmp.json
	jq . "${subjects_dir}"/tmp.json > "${subjects_dir}"/config.json && rm "${subjects_dir}"/tmp.json	
	####################################################################################################################
	# done! exit with clean error code if you made it this far
	return 0				
}
export -f check_freesurfer_subject
############################################################################################################################################
# --------------------------------------------> 													   			   Check | FreeSurfer | JSON
############################################################################################################################################
# TODO add link
# TODO add doi
# TODO check if subject names in BIDS format
function check_freesurfer_json(){
	local subjects_dir=${1} && shift
	local subjects_dir_size="$(du -d 1 -c -h ${subjects_dir} | grep 'total' | awk '{print $1}')"
	local subjects_dir_num=$(find "${subjects_dir}"/ -name 'recon-all.log' -type f | wc -l)
	############################################################################################
	# Create JSON template
	############################################################################################
	# can use jq to do this?
	jq -n '{"Description": FreeSurfer Subjects Directory Metadata, "SubjectsDirectory": "'${subjects_dir}'","SubjectsDirectorySize":"'${subjects_dir_size}'"}'
read -r -d '' json <<EOF
{
	"Description": "FreeSurfer Subjects Directory Metadata",
	"SubjectsDirectory": "${subjects_dir}",
	"SubjectsDirectorySize": "${subjects_dir_size}",
	"SubjectsDirectoryNumber": ${subjects_dir_num},
	"Subjects": null
}
EOF
	############################################################################################
	# Print to Configuration File
	############################################################################################
	echo "${json}" > "${subjects_dir}"/config.json
	############################################################################################
	# Add Subjects Object
	############################################################################################
	local str="$(printf '"%s": null, ' $(find "${subjects_dir}"/ -name 'recon-all.log' | awk '{print $NF}' | sed "s|${subjects_dir}||g" | sed "s|/| |g" | awk '{print $1}' | sort -u) | sed 's/\(.*\),/\1 /')"
	jq '.Subjects = {'"${str}"'}' "${subjects_dir}"/config.json > "${subjects_dir}"/tmp.json
	jq . "${subjects_dir}"/tmp.json > "${subjects_dir}"/config.json && rm "${subjects_dir}"/tmp.json
}
export -f check_freesurfer_json
############################################################################################################################################
# --------------------------------------------> 															Check | FreeSurfer Subject Files
############################################################################################################################################
## 
function check_freesurfer_suject_manifest(){
	local subject="${1}" && shift
	local subjects_dir="${1}" && shift
	local manifest=$(cat ${1})
	############################################################################################
	# Defaults
	############################################################################################
	local numfiles=$(echo "${manifest}" | wc -l)
	local numsubfiles=''
	EXISTS=('')
	MISSING=('')	
	RERUNSUB='null'
	COMPLETESUB='null'
	############################################################################################
	printf "\r\033[K${GREY}File Manifest Validation :: ${BLUE}%s${NC}" "${subject}"
	############################################################################################
	# Check for File Manifest
	############################################################################################
	if [ ! -f "${manifest}" ]; then 
		printf '\r\033[K${BRED}◀︎|⁃‣ERROR${NC} Manifest File Not Found :: %s ' "${1}"
		return 1
	fi	
	# now loop across files
	for file in ${manifest}; do
		if [ "$(find "${subjects_dir}/${subject}" \( ! -regex '.*/\..*' \) -name "${file}" )" ]; then
			EXISTS+=("${file}")
		else
			MISSING+=("${file}")
		fi
	done
	# set default JSON null val
	[ ! "${EXISTS[@]}" ] && EXISTS=('null')
	[ ! "${MISSING[@]}" ] && MISSING=('null')
	############################################################################################
	# Check if Average and Complete or Needs Rerun
	############################################################################################
	numsubfiles=$(printf '%s\n' "${EXISTS[@]}" | wc -l)
	if echo ${subject} | grep -qE '.?average'; then
		if [ "${numsubfiles}" -lt "48" ]; then
			RERUNSUB='true'
		else
			COMPLETESUB='true'
		fi			
	else
		if [ "${numsubfiles}" != "${numfiles}" ]; then
			RERUNSUB='true'
		else
			COMPLETESUB='true'
		fi
	fi
	############################################################################################
	# got this far? done! exit with clean error code
	return 0
}
############################################################################################################################################
# --------------------------------------------> 											   							 Make SGE Job Script
############################################################################################################################################
# TODO check queue existence
# TODO check if jobname already exists
function preproc_make_job(){
	local sgeworkdir="${1}" && shift
	local subject="${1}" && shift
	local jobname="${1}" && shift
	local queue="${1}" && shift
	local command="${@}"
	[ ! -d "${sgeworkdir}" ] && mkdir -pv ${sgeworkdir}
# auto-generate script
cat > "${sgeworkdir}"/"${subject}"-"${jobname}"'.sh' <<EOF 
#!/bin/bash
#$ -S /usr/local/bin/bash
#$ -q ${queue}
#$ -N ${jobname}-${subject}
#$ -o ${jobname}-${subject}-stdout.log
#$ -e ${jobname}-${subject}-stderr.log
##
${command}
exit
EOF
	# set permission
	chmod 755 "${sgeworkdir}"/"${subject}"-"${jobname}"'.sh'
	# done
	return
}
export -f preproc_make_job
############################################################################################################################################
# --------------------------------------------> 																	   Submit SGE Job Script
############################################################################################################################################
function preproc_submit_job(){
	local sgeworkdir="${1}"
	local subject="${2}" 
	local jobname="${3}"
	# submit
	qsub -V -w e -wd "${sgeworkdir}" "${sgeworkdir}"/"${subject}"-"${jobname}"'.sh'
	# done
	return 
}
export -f preproc_submit_job
############################################################################################################################################
# --------------------------------------------> 																  Preprocess | T1w | Denoise
############################################################################################################################################
## Main Function for Denoising
## This function takes data for a single subject as input and performs N4 Bias Field Correction Followed by 
## Non-Local-Means Denoising assuming a Rician Distribution and a 1x1x1mm patch size. Bias field and noise
## estimates are saved in the output directory.
##
function preproc_structural_denoise(){
	local IN=${1} && local DIR=${2}
	########################################################
	# Defaults
	########################################################
	local OUT="${DIR}/$(echo "${IN}" | sed 's|/| |g' | awk '{print $NF}' | sed 's|.nii.gz|_N4.nii.gz|g')"
	# Noise Model can be Rician or Gaussian
	local noisemodel='Rician'
	local overwrite=${3}
	if [ ! -f "${IN}" ]; then
		>&2 echo -e "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} :: ${IN} not found on system, check source data"
		return 1
	fi
	########################################################
	# Deoblique Images (remove angle)
	# TODO test
	########################################################
	if [ "${overwrite}" ] || [ ! -f "${OUT}" ]; then
		if 3dWarp -deoblique -prefix "$(echo "${IN}" | sed 's|/| |g' | awk '{print $NF}')" "${IN}" >&1; then
			>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} 3dWarp -deoblique -prefix $(echo "${IN}" | sed 's|/| |g' | awk '{print $NF}') ${IN}"
		else
			>&2 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} 3dWarp -deoblique -prefix $(echo "${IN}" | sed 's|/| |g' | awk '{print $NF}') ${IN}"
			return 1
		fi
	else
		>&3 printf "\r\033[KFile Exists No Overwrite :: ${GREY}%s ${NC}\r" ${OUT}		
	fi	
	IN="${DIR}/$(echo "${IN}" | sed 's|/| |g' | awk '{print $NF}')"
	########################################################
	# N4 Denoise
	########################################################
	if [ "${overwrite}" ] || [ ! -f "${OUT}" ]; then
		if ${ANTSPATH}/N4BiasFieldCorrection -d 3 -i "${IN}" -o ["${OUT}","$(echo "${OUT}" | sed 's|N4|N4BiasField|g')"] >&1; then
			>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} ${ANTSPATH}/N4BiasFieldCorrection -d 3 -i ${IN} -o [${OUT},$(echo ${OUT} | sed 's|N4|N4BiasField|g')]"
		else
			>&2 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} ${ANTSPATH}/N4BiasFieldCorrection -d 3 -i ${IN} -o [${OUT},$(echo ${OUT} | sed 's|N4|N4BiasField|g')]"
			return 1
		fi
	else
		>&3 printf "\r\033[KFile Exists No Overwrite :: ${GREY}%s ${NC}\r" ${OUT}		
	fi
	########################################################
	# NLM Denoise with Rician Distribution Approximation
	########################################################
	IN=${OUT}
	OUT=$(echo ${IN} | sed "s|N4|N4_${noisemodel}Denoised|g")
	if [ "${overwrite}" ] || [ ! -f "${OUT}" ]; then
		if ${ANTSPATH}/DenoiseImage -n "${noisemodel}" -d 3 -i "${IN}" -o ["${OUT}",$(echo "${OUT}" | sed "s|${noisemodel}Denoised|${noisemodel}EstmNoise|g")] >&1; then
			>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} ${ANTSPATH}/DenoiseImage -n ${noisemodel} -d 3 -i ${IN} -o [${OUT},$(echo ${OUT} | sed "s|${noisemodel}Denoised|${noisemodel}EstmNoise|g")]"
		else
			>&2 printf "\r$\033[K{BRED}◀︎|⁃‣ERROR${NC} ${ANTSPATH}/DenoiseImage -n ${noisemodel} -d 3 -i ${IN} -o [${OUT},$(echo ${OUT} | sed "s|${noisemodel}Denoised|${noisemodel}EstmNoise|g")]"
			return 1
		fi
	else
		>&2 printf "\r\033[KFile Exists No Overwrite :: ${GREY}%s ${NC}\r" ${OUT}		
	fi
	########################################################
	# done
	########################################################
	return 0
}
export -f preproc_structural_denoise
############################################################################################################################################
# --------------------------------------------> 												  Preprocess | T1w | Study Specific Template
############################################################################################################################################
## Create T1w Study Specific Template!
## This function retrieves N4 bias corrected + Rician NLM denoised T1w scans from 55 selected participants and 
## uses a predefined template as an initialization template to generate a further refined/more detailed template. 
##
## To successfully run this function you must have an SST covariates sheet. The name of template will be derived
## from the name of this covariates sheet. The best runs for each subject will be selected using the 
## bestrun-$modality column. This function will exit with an error if there is not bestrun-$modality column for
## each modality input. All files for subjects are checked before assembling input list for tempalte construction.
## Subjects with missing data are excluded from template construction. Output T1w image is rigid registered to
## user-defined template following template contruction. All images are sharpened after template construction.
#
## The default parameters for template construction have been tuned to the following:
##      - Increasing the number of iterations from 4 - 5
##      - Using the mean intensity instead of the mean normalized intensity (more contrast)
##      - Decreasing the Neighborhood of the Cross-Correlation from 4 to 1 (more local detail)
##      - Decreasing the gradient step size to 0.01
##      - Setting 100x100x100x70x70x30 pairwise iterations for 10x8x6x4x2x1 and 6x4x2x1x0 shrink/smooth factors
##
## Full list of options:
## * antsMultivarateTemplateConstruction2.sh parameters
## 		-a 0|1			:: 	mean of normalized intensities used to summarize images
## 		-d 1-n			::	image dimension
## 		-c 0|1			::	SGE 
## 		-n 0|1			::	intensity correction (already performed)
## 		-k 1-n 			::	number of modalities
## 		-r 0|1 			::	rigid-body registration + average for target
## 		-z 0|1 			::	initialize with external template
## 		-t SyN 			::	Type of Transform (Syn=Greedy SyN, RI=Rigid .. see ANTS doc)
## 		-m CC 			::	Similarity metric (CC=CrossCorrelation, MI=Mutual Information .. see ANTS doc)
## 		-i 1-n 			::	Number of iterations
## 		-g 0-n 			::	Gradient step size (smaller takes longer)
## 		-q NxMxRxP		::	Max iterations for each pairwise registration
## 		-s NxMxRxPx1x0	:: 	Smoothing factors
## 		-f NxMxRxP		::	Shrink factors
##
function preproc_structural_ants_sst(){
	############################################################################################
	# define local variables
	############################################################################################
	local sstname="${1}" && shift
	local INDIR="${1}" && shift
	local OUTDIR="${1}" && shift
	local modality="${@}"
	pushd "${OUTDIR}"
	############################################################################################
	# check for input existence
	############################################################################################
	[ ! -d "${INDIR}" ]  && >&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} Input Data Directory Cannot be Resolved ${NC}" && return 1
	[ ! -d "${OUTDIR}" ] && >&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} Output Data Directory Cannot be Resolved ${NC}" && return 1
	[ ! -f "${SSTCOV}" ] && >&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} Study Specific Template Covariates File Cannot be Parsed ${NC}" && return 1
	[ ! "${modality}" ]  && >&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} Input Modality Not Specified${NC}" && return 1
	############################################################################################
	# get best run # for each modality
	############################################################################################
	local counter=1 && local bestrunind=()
	for header in $(head -n +1 "${SSTCOV}"); do
		for m in ${modality}; do
			if echo "${header}" | grep "${m}-best-run" 1>/dev/null 2>/dev/null; then
				bestrunind+=(${counter})
			fi
		done
		((counter++))
	done
	############################################################################################
	# check to make sure there is a bestrun index for each modality
	############################################################################################
	if [ ! ${bestrunind} ]; then
		>&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} Can not find 'best-run-MODALITY' column in ${SSTCOV}${NC}"
		return 1
	elif [ $(echo ${bestrunind[@]} | wc -w) != $(echo "${modality}" | wc -w) ]; then
		>&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} Mismatch - number of input modalities does not match ${SSTCOV}, check header syntax matches 'best-run-MODALITY'${NC}"
		return 1
	fi
	############################################################################################
	# parse list of participants for study specific template to create file names
	############################################################################################
	local files=() && local counter=0
	for m in ${modality}; do
		files+=($(tail -n +2 "${SSTCOV}" | awk -v var="${m}" '{ printf "%s_ses-wave%s_run-0%s_%s_N4_RicianDenoised.nii.gz\n", $1,$2,$'${bestrunind[$counter]}',var }'))
		((counter++))
	done
	############################################################################################
	# check for existence of individual files and compile list
	############################################################################################
	local FILES=() && local missing=()
	for f in "${files[@]}"; do
		if [ "$(find "${INDIR}" -name "${f}")" ]; then
			FILES+=("$(find ${INDIR} -name ${f})")
		else
			missing+=($(echo "${f}"))
			>&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} File for SST ${GREY}${f}${NC} not found"
		fi
	done
	############################################################################################
	# only select those participants with existence of all modalities 
	# (must have complete list of files for sst)
	############################################################################################
	sessions=$(printf '%s\n' "${FILES[@]}" | sed 's|/| |g' | awk '{print $NF}' | sed 's|_run| |g' | awk '{print $1}' | sort -u)
	[ -f "${OUTDIR}"/inputfiles.txt ]  && >&3 rm -v "${OUTDIR}"/inputfiles.txt
	for s in ${sessions}; do
		num_modalities_for_sess=$(echo "${FILES[@]}" | grep -oE "${s}" | wc -l)
		# only include subject if number of found modalities = to total number of modalities
		if [ ${num_modalities_for_sess} -eq $(echo "${modality}" | wc -w) ]; then
			printf "${INDIR}/%s,${INDIR}/%s\n" $(echo "${FILES[@]}" | grep -oE "(${s}_run-0[1-9]_\w*?_N4_RicianDenoised\.nii\.gz)") >> "${OUTDIR}"/inputfiles.txt
		else
			>&3 printf "\r\033[K${YELLOW}WARNING :: ${NC}${s} not included in SST creation, incomplete dataset - check ${SSTCOV}"
		fi
	done
	############################################################################################
	# create template with specified modalities and default settings
	############################################################################################
	>&3 printf "\n ${BLUE}Multivariate Template Construction ${GREY}"
	if "${ANTSPATH}"/antsMultivariateTemplateConstruction2.sh \
		-a 0 -n 0 -d 3 -c 1 -k $(echo "${modality}" | wc -w) -b 1 \
        -z "${SSTINIT}" \
		-t SyN -m ${SST_SIMILARITYMETRIC} -f ${SST_SHRINKFACTOR} -s ${SST_SMOOTH} \
		-i 5 -g 0.01 -q ${SST_NUMQITER} \
		-o "${OUTDIR}"/"${sstname}" \
		"${OUTDIR}"/inputfiles.txt >&3; then
			>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} ${ANTSPATH}/antsMultivariateTemplateConstruction2.sh -a 0 -n 0 -d 3 -c 1 -k $(echo ${modality} | wc -w) -b 1 -z ${SSTINIT} -t SyN -m ${SST_SIMILARITYMETRIC} -f ${SST_SHRINKFACTOR} -s ${SST_SMOOTH} -i 5 -g 0.01 -q ${SST_NUMQITER} -o ${OUTDIR}/${sstname} ${OUTDIR}/inputfiles.txt"
	else
			>&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} ${ANTSPATH}/antsMultivariateTemplateConstruction2.sh -a 0 -n 0 -d 3 -c 1 -k $(echo ${modality} | wc -w) -b 1 -z ${SSTINIT} -t SyN -m ${SST_SIMILARITYMETRIC} -f ${SST_SHRINKFACTOR} -s ${SST_SMOOTH} -i 5 -g 0.01 -q ${SST_NUMQITER} -o ${OUTDIR}/${sstname} ${OUTDIR}/inputfiles.txt"
			return 1
	fi
	############################################################################################
	# sharpen (better for edge detection)
	############################################################################################
	counter=0
	for m in ${modality}; do
		>&3 printf "${BLUE}   Sharpening Template and writing to ${OUTDIR}/${sstname}sst-${m}.nii.gz${GREY}\n"
		if "${ANTSPATH}"/ImageMath 3 "${OUTDIR}"/"${sstname}"sst-"${m}".nii.gz Sharpen "${OUTDIR}"/"${sstname}"template${counter}.nii.gz >&3 ; then
			>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} ${ANTSPATH}/ImageMath 3 ${OUTDIR}/${sstname}sst-${m}.nii.gz Sharpen ${OUTDIR}/${sstname}template${counter}.nii.gz"
		else
			>&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} ${ANTSPATH}/ImageMath 3 ${OUTDIR}/${sstname}sst-${m}.nii.gz Sharpen ${OUTDIR}/${sstname}template${counter}.nii.gz"
			return 1
		fi
		if [ "${m}" = 'T1w' ]; then
			>&3 printf "${BLUE}   Rigid-Registering SST-T1w to MNI Space : ${GREY}${MNITEMPLATE}${GREY}\n"
	############################################################################################
	# compute linear warp to MNI152
	############################################################################################
			if "${ANTSPATH}"/antsIntroduction.sh \
		    	-d 3 -i "${OUTDIR}"/"${sstname}"sst-"${m}".nii.gz \
		    	-r "${MNITEMPLATE}" \
		    	-n 0 -t RI -s CC \
		    	-o "${OUTDIR}"/"${sstname}"sst-"${m}"_mni-rr_ >&3; then
		    	>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} ${ANTSPATH}/antsIntroduction.sh -d 3 -i ${OUTDIR}/${sstname}sst-${m}.nii.gz -r ${MNITEMPLATE} -n 0 -t RI -s CC -o ${OUTDIR}/${sstname}sst-${m}_mni-rr_"	
		    else
				>&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} ${ANTSPATH}/antsIntroduction.sh -d 3 -i ${OUTDIR}/${sstname}sst-${m}.nii.gz -r ${MNITEMPLATE} -n 0 -t RI -s CC -o ${OUTDIR}/${sstname}sst-${m}_mni-rr_"			    	
				return 1
		    fi
		fi
		((counter++))
	done
	# return where you started
    popd
	############################################################################################
	# got this far? done! exit with clean error code    
    return 0
}
export -f preproc_structural_ants_sst
############################################################################################################################################
# --------------------------------------------> 							         Preprocess | T1w | Study Specific Template | FreeSurfer
############################################################################################################################################
# TODO test
function preproc_structural_ants_sst_freesurfer(){
	local sstdir=${1} && shift
	local bidsdir=${1} && shift
	local queue=${1} && shift
	local sstname=${1} && shift
	local overwrite=${1} && shift
	# defaults
	local subjects=$(find "${sstdir}" -d 1 -name "*WarpedToTemplate.nii.gz" | sed 's|/| |g' | awk '{print $NF}' | sed 's|template0| |g' | awk '{print $NF}' | sed 's|_T1w| |g' | awk '{print $1}' | sort -u)
	local command=''
	# check if there are subjects warped to template in working directory
	[ ! "${subjects}" ] && printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} No Template-Warped Images found in ${sstdir}" && return 1
	# initialize recons in working directory 
	SUBJECTS_DIR=${sstdir}/recons && export SUBJECTS_DIR
	[ ! -d "${SUBJECTS_DIR}" ] && mkdir -pv "${SUBJECTS_DIR}"
	>&3 printf  "\r\033[KCortical Surface Reconstruction for: ${GREY}%s ${NC}" ${sstname}
	for subject in ${subjects}; do
		# definitions
		local T1w="$(find "${sstdir}" -d 1 -name "*${subject}_T1w*WarpedToTemplate.nii.gz")"
		local T2w="$(find "${sstdir}" -d 1 -name "*${subject}_T2w*WarpedToTemplate.nii.gz")"
		# check for existence of data
		if [ ! -d "${SUBJECTS_DIR}/${subject}" ]; then
			if [ "${T1w}" ] && [ "${T2w}" ]; then
				local command="${FREESURFER_HOME}/bin/recon-all -sd ${SUBJECTS_DIR} -s ${subject} -i ${T1w} -T2 ${T2w} -T2pial -parallel -expert ${bidsdir}/code/fs-expert-opts.txt -xopts-use -xopts-overwrite -all"
			elif [ "${T1w}" ] && [ ! "${T2w}" ]; then
				local command="${FREESURFER_HOME}/bin/recon-all -sd ${SUBJECTS_DIR} -s ${subject} -i ${T1w} -parallel -expert ${bidsdir}/code/fs-expert-opts.txt -xopts-use -xopts-overwrite -all"					
			else
				>&2 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} Cannot Find T1w OR T2w for image ${subject} used to create ${sstdir}/${sstname}sst.nii.gz" 
			fi
		else
			>&3 printf  "\r\033[KSubject Exists: ${GREY}%s ${NC}\r" ${SUBJECTS_DIR}/${subject}
		fi
		# rerun only if user indicates overwrite
		if [ -d "${SUBJECTS_DIR}/${subject}" ] && [ "${overwrite}" ]; then
			>&3 printf  "\r\033[KOverwriting Subject Recon: ${BLUE}%s ${NC}\r" ${SUBJECTS_DIR}/${subject}
			if [ "${T1w}" ] && [ "${T2w}" ]; then
				local command="${FREESURFER_HOME}/bin/recon-all -sd ${SUBJECTS_DIR} -s ${subject} -T2 ${T2w} -T2pial -parallel -expert ${bidsdir}/code/fs-expert-opts.txt -xopts-use -xopts-overwrite -all"
			elif [ "${T1w}" ] && [ ! "${T2w}" ]; then
				local command="${FREESURFER_HOME}/bin/recon-all -sd ${SUBJECTS_DIR} -s ${subject} -parallel -expert ${bidsdir}/code/fs-expert-opts.txt -xopts-use -xopts-overwrite -all"					
			else
				>&2 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} Cannot Find T1w OR T2w for image ${subject} used to create ${sstdir}/${sstname}sst.nii.gz" 
			fi
		fi
		# run if command is defined
		if [ "${command}" ]; then
			## --> write job submission scripts
			if preproc_make_job ${SUBJECTS_DIR}/sgeworkdir ${subject} "${sstname}recon" ${queue} ${command}; then
				>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} preproc_make_job ${SUBJECTS_DIR}/sgeworkdir ${subject} ${sstname}recon ${queue} ${command}"
			else
				>&2 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} preproc_make_job ${SUBJECTS_DIR}/sgeworkdir ${subject} ${sstname}recon ${queue} ${command}"
				return 1
			fi			
			## --> submit jobs
			if preproc_submit_job ${SUBJECTS_DIR}/sgeworkdir ${subject} "${sstname}recon"; then
				>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} preproc_submit_job ${SUBJECTS_DIR}/sgeworkdir ${subject} ${sstname}recon"
			else
				>&2 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} preproc_submit_job ${SUBJECTS_DIR}/sgeworkdir ${subject} ${sstname}recon"			
				return 1
			fi	
		fi			
	done
	# populate json config while waiting for jobs to complete
	while [ "$(echo -e $(qstat -xml | sed 's#<job_list[^>]*>#\\n#g' | sed 's#<[^>]*>##g') | grep "${sstname}recon")" ]; do
		for subject in ${subjects}; do
			check_freesurfer_subject ${subject} "${SUBJECTS_DIR}"
		done
	done	
	# TODO only proceed if all subjects exist and are successfully completed
	# CHECK CONFIG FILE FOR ALL SUBJECTS COMPLETE
	# create average subject
	if preproc_structural_ants_sst_freesurfer_average ${sstdir} ${SUBJECTS_DIR} ${sstname} ${overwrite}; then
		>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} preproc_structural_ants_sst_freesurfer_average ${sstdir} ${SUBJECTS_DIR} ${sstname} ${overwrite}"
	else
		>&2 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} preproc_structural_ants_sst_freesurfer_average ${sstdir} ${SUBJECTS_DIR} ${sstname} ${overwrite}"		
		return 1
	fi
	# done! exit with no-error if you got this far
	return 0
}
############################################################################################################################################
# --------------------------------------------> 							 Preprocess | T1w | Study Specific Template | FreeSurfer Average
############################################################################################################################################
# TODO test
# >&2 echo -e "  🕷🔨 ${YELLOW}DEBUG${NC} surfergems_makeavg $@ (${SECONDS}s elapsed)"	
function preproc_structural_ants_sst_freesurfer_average(){
	local sstdir=${1} && shift
	local SUBJECTS_DIR=${1} && shift && export SUBJECTS_DIR
	local averagename="${1}average" && shift
	local overwrite="${1}" && shift
	subjects=$(find "${sstdir}" -d 1 -name "*WarpedToTemplate.nii.gz" | sed 's|/| |g' | awk '{print $NF}' | sed 's|template0| |g' | awk '{print $NF}' | sed 's|_T1w| |g' | awk '{print $1}' | sort -u)
	# now check for existing or whether user wants to overwrite
	if [ $(echo ${subjects} | wc -w ) -lt 2 ]; then
		>&3 printf "\r\033[K${BRED}✖︎  cannot create average with a single subject"
		return 1
	else
		>&2 printf  "\r\033[KComputing Average Subject Surface: ${GREY}%s ${NC}\r" "${SUBJECTS_DIR}"/"${averagename}"
	fi
	# overwrite average subject is user indicates
	if [ "${overwrite}" ] || [ ! -d "${SUBJECTS_DIR}/${averagename}" ]; then
		[ "${overwrite}" ] && [ -d "${SUBJECTS_DIR}/${averagename}" ] && rm -vr "${SUBJECTS_DIR}/${averagename}"
			if "${FREESURFER_HOME}"/bin/make_average_subject --subjects "${subjects}" \
														--sd "${SUBJECTS_DIR}" \
														--out "${averagename}" >&3
			then
				>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} ${FREESURFER_HOME}/bin/make_average_subject --subjects ${subjects} --sd ${SUBJECTS_DIR} --out ${averagename}"
			else
				>&2 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC}  ${FREESURFER_HOME}/bin/make_average_subject --subjects ${subjects} --sd ${SUBJECTS_DIR} --out ${averagename} FAILED"
				return 1
			fi
	else
		>&3 printf "\r\033[K${BLUE}◀︎|⁃‣NO OVERWRITE - AVERAGE SUBJECT EXISTS :: ${GREY}${SUBJECTS_DIR}/${averagename}${NC}"		
	fi
	# compute registration for all subjects to average
	>&3 printf "\r\033[K${YELLOW}⮑  registering subjects to ${SUBJECTS_DIR}/${averagename}${NC}\n"
	if parallel -k --link preproc_structural_ants_sst_freesurfer_average_register {} "${SUBJECTS_DIR}" "${averagename}" "${overwrite}" ::: ${subjects}; then
		>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} preproc_structural_ants_sst_freesurfer_average_register {} ${SUBJECTS_DIR} ${averagename}  ${overwrite} ::: $(echo "${SUBJECTS[@]}" | sed "s|${averagename}||g")\n"
	else
		>&2 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} preproc_structural_ants_sst_freesurfer_average_register {} ${SUBJECTS_DIR} ${averagename} ${overwrite} ::: $(echo "${SUBJECTS[@]}" | sed "s|${averagename}||g")\n"
		return 1
	fi
	# done! exit with no-error if you got this far
	return 0
}
export -f preproc_structural_ants_sst_freesurfer_average
############################################################################################################################################
# --------------------------------------------> 		  Preprocess | T1w | Study Specific Template | FreeSurfer Average | Register Subject
############################################################################################################################################
# TODO test
# >&2 echo -e "  🕷🔨 ${YELLOW}DEBUG${NC} surfergems_makeavg $@ (${SECONDS}s elapsed)"	
function preproc_structural_ants_sst_freesurfer_average_register(){
	local subject="${1}" && shift
	SUBJECTS_DIR="${1}" && shift && export SUBJECTS_DIR	
	local averagename="${1}" && shift
	local overwrite="${1}" && shift
	if [ ! -f "${SUBJECTS_DIR}/${subject}/mri/brain.mgz" ]; then
		>&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR: Required file does not exist %s ${NC}" "${SUBJECTS_DIR}"/"${subject}"/mri/brain.mgz
		return 1
	fi
	if [ "${overwrite}" ] || [ ! -f "${SUBJECTS_DIR}/${subject}/mri/transforms/registration-to-${averagename}.dat" ]; then
		if "${FREESURFER_HOME}"/bin/fslregister --s "${averagename}" \
										  --mov "${SUBJECTS_DIR}/${subject}/mri/brain.mgz" \
					   				  	  --reg "${SUBJECTS_DIR}/${subject}/mri/transforms/registration-to-${averagename}.dat" \
					   				  	  --dof 12; then
			>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} ${FREESURFER_HOME}/bin/fslregister --s ${averagename} --mov ${SUBJECTS_DIR}/${subject}/mri/brain.mgz --reg ${SUBJECTS_DIR}/${subject}/mri/transforms/registration-to-${averagename}.dat --dof 12\n"
		else
			>&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR: fslregister ${subject} to ${averagename} failed ${NC}"
			return 1
		fi					
	else
		>&3 printf "\r\033[K${BLUE}◀︎|⁃‣NO OVERWRITE - TRANSFORM TO AVERAGE SUBJECT EXISTS :: ${GREY}${SUBJECTS_DIR}/${subject}/mri/transforms/registration-to-${averagename}.dat${NC}"				
	fi
	# done! exit with no-error if you got this far
	return 0
}
export -f preproc_structural_ants_sst_freesurfer_average_register
############################################################################################################################################
# --------------------------------------------> 											       					 Preprocess | FreeSurfer
############################################################################################################################################
# TODO freesurfer pre-checks
# TODO option input
function preproc_structural_freesurfer(){
	local sourcedata=${1}
	local subject=${2}
	SUBJECTS_DIR=${3} && export SUBJECTS_DIR
	BIDSDIR=${4}
	# sgeworkdir
	# queue
	# sst	
	# sstname	
	# 1] check for structural existence
	T1w=$(find ${sourcedata}/ -name "${subjectid}*T1w*Denoised.nii.gz")
	T2w=$(find ${sourcedata}/ -name "${subjectid}*T2w*Denoised.nii.gz")
	# 2] run skullstripping based on T1w/T2w existence
	# 	 - expert options are used to perform gentle intensity bias correction
	##   --> run both T1w and T2w if they both exist
	if [ "${T1w}" ] && [ "${T2w}" ]; then
		local command="${FREESURFER_HOME}/bin/recon-all -sd ${SUBJECTS_DIR} -s ${subject} -i ${T1w} -T2 ${T2w} -parallel -expert ${BIDSDIR}/code/fs-expert-opts.txt -xopts-use -xopts-overwrite ${fsopts}"
		preproc_make_job ${sgeworkdir} ${subject} 'sklstrp' ${queue} ${command}
		preproc_submit_job ${sgeworkdir} ${subject} 'sklstrp'
	## 	--> run only with T1w if T2w doesn't exist
	elif [ "${T1w}" ] && [ ! "${T2w}" ]; then
		local command="${FREESURFER_HOME}/bin/recon-all -sd ${SUBJECTS_DIR} -s ${subject} -i  ${T1w} -parallel -expert ${BIDSDIR}/code/fs-expert-opts.txt -xopts-use -xopts-overwrite ${fsopts}"
		preproc_make_job ${sgeworkdir} ${subject} 'sklstrp' ${queue} ${command}
		preproc_submit_job ${sgeworkdir} ${subject} 'sklstrp'
	else
		echo -e "${BRED}ERROR ::: T1w or T2w image not found for ${subjectid}, check system and/or manifest"
	fi
}
############################################################################################################################################
# --------------------------------------------> 											       		 Preprocess | Brain Mask | Watershed
############################################################################################################################################
# This function checks whether a T2w / T1w image pair exists for each subject and performs watershed-based skull stripping
# 	 - expert options are used to perform gentle intensity bias correction
# TODO allow switching between SGE and PARALLEL
# TODO check for isrunning
function preproc_structural_brainmask_watershed(){
	local sourcedata="${1}" && shift
	local subject="${1}" && shift
	local bidsdir="${1}" && shift
	SUBJECTS_DIR="${1}" && export SUBJECTS_DIR && shift
	local queue="${1}" && shift
	local overwrite="${1}" 
	##################################################
	# defaults
	##################################################
	local sourcedatasuffix='RicianDenoised.nii.gz'
	local command='echo "skipping sklstrp-${subject}"; return 0'
	# check for T1 and T2w image (required for optimal freesurfer watershed)
	local T1w=$(find "${sourcedata}" -name "${subject}*T1w*${sourcedatasuffix}")
	local T2w=$(find "${sourcedata}" -name "${subject}*T2w*${sourcedatasuffix}")
	# check for expert opts existence
	[ ! -f "${bidsdir}/code/fs-expert-opts.txt" ] && >&2 echo -e "${BRED} ERROR !! Cannot find expert options ${bidsdir}/code/fs-expert-opts.txt" && return 1
	# run skullstripping based on T1w/T2w existence
	##################################################	
	##   --> run both T1w and T2w if they both exist
	##################################################
	if [ "${T1w}" ] && [ "${T2w}" ]; then
		## --> do not rerun if brainmask already exists
		if [ ! -f "${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz" ]; then
			# remove subject directory if brainmask missing and reproc
			[ -d "${SUBJECTS_DIR}/${subject}" ] && rm -rv "${SUBJECTS_DIR}/${subject}"
			local command="${FREESURFER_HOME}/bin/recon-all -sd ${SUBJECTS_DIR} -s ${subject} -i ${T1w} -T2 ${T2w} -parallel -expert ${bidsdir}/code/fs-expert-opts.txt -xopts-use -xopts-overwrite -autorecon1"
		else
			printf  "\r\033[KSkull Stripped File Exists: ${GREY}%s ${NC}\r" ${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz
		fi
		## --> only rerun with overwrite flag
		if [ -f "${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz" ] && [ ${overwrite} ]; then
			printf "\r\033[K${BLUE}Overwriting ${GREY}%s ${NC}" ${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz
			local command="${FREESURFER_HOME}/bin/recon-all -sd ${SUBJECTS_DIR} -s ${subject} -T2 ${T2w} -parallel -expert ${bidsdir}/code/fs-expert-opts.txt -xopts-use -xopts-overwrite -autorecon1"			
		else
			>&3 printf "\r\033[KNo Overwrite :: ${GREY}%s ${NC}\r" ${OUT}
			return 0
		fi	
		## --> create job sumbission scripts
		if preproc_make_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'sklstrp' ${queue} ${command}; then
			printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} preproc_make_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'sklstrp' ${queue} ${command}"
		else
			printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} preproc_make_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'sklstrp' ${queue} ${command}"
			return 1
		fi
		## --> submit jobs
		if preproc_submit_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'sklstrp'; then
			printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} preproc_submit_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'sklstrp'"
		else
			>&2 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} preproc_submit_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'sklstrp'"			
			return 1
		fi
	##################################################		
	## 	--> run only with T1w if T2w doesn't exist
	##################################################
	elif [ "${T1w}" ] && [ ! "${T2w}" ]; then
		if [ ! -f "${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz" ]; then
			local command="${FREESURFER_HOME}/bin/recon-all -sd ${SUBJECTS_DIR} -s ${subject} -i  ${T1w} -parallel -expert ${bidsdir}/code/fs-expert-opts.txt -xopts-use -xopts-overwrite -autorecon1"
		else
			printf  "\r\033[KSkull Stripped File Exists: ${GREY}%s ${NC}\r" ${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz
		fi
		## --> only rerun with overwrite flag
		if [ -f "${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz" ] && [ ${overwrite} ]; then
			printf "\r\033[K${BLUE}Overwriting ${GREY}%s ${NC}" ${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz
			local command="${FREESURFER_HOME}/bin/recon-all -sd ${SUBJECTS_DIR} -s ${subject} -parallel -expert ${bidsdir}/code/fs-expert-opts.txt -xopts-use -xopts-overwrite -autorecon1"
		else
			>&3 printf "\r\033[KNo Overwrite :: ${GREY}%s ${NC}\r" ${OUT}
			return 0		
		fi				
		if preproc_make_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'sklstrp' ${queue} ${command}; then
			printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} preproc_make_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'sklstrp' ${queue} ${command}"
		else
			>&2 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} preproc_make_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'sklstrp' ${queue} ${command}"
			return 1
		fi			
		## --> submit jobs
		if preproc_submit_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'sklstrp'; then
			printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} preproc_submit_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'sklstrp'"
		else
			>&2 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} preproc_submit_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'sklstrp'"			
			return 1
		fi
	else
		>&2 echo -e "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} T1w or T2w image not found for ${subjectid}, check system and/or manifest"
		return 1
	fi	
	# exit with clean no-error exit if you made it this far!
	return 0
}
export -f preproc_structural_brainmask_watershed
############################################################################################################################################
# --------------------------------------------> 											   Preprocess | T1w | Brain Mask | Probabilistic
############################################################################################################################################
# TODO should check status of subject.. file could already exist but not be the right one in the case of an overwrite
# --> you can use Surfer-gems for this at some point
# TODO can add success signal at the end of job submission script
# TODO check for SGE!!
# TODO move away from FSL (crappy license)
# TODO fix standard error/output (too messy!)
function preproc_structural_brainmask_prob_subject(){
	local sourcedata="${1}" && shift
	local subject="${1}" && shift
	local bidsdir="${1}" && shift
	SUBJECTS_DIR="${1}" && export SUBJECTS_DIR && shift
	local sst=${1} && shift
	local queue=${1} && shift
	local overwrite="${1}"
	##################################################		
	## 	1 --> run watershed brain extraction
	##################################################	
	if preproc_structural_brainmask_watershed ${sourcedata} ${subject} ${bidsdir} ${SUBJECTS_DIR} ${queue} ${overwrite} 2>&2 1>&3; then
		>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} preproc_structural_brainmask_watershed ${sourcedata} ${subject} ${bidsdir} ${SUBJECTS_DIR} ${queue} ${overwrite}"
	else
		>&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} preproc_structural_brainmask_watershed ${sourcedata} ${subject} ${bidsdir} ${SUBJECTS_DIR} ${queue} ${overwrite}"
		return 1
	fi
	# wait for jobs to complete
	while [ "$(echo -e $(qstat -xml | sed 's#<job_list[^>]*>#\\n#g' | sed 's#<[^>]*>##g') | grep "sklstrp-${subject}")" ]; do
		# >&3 printf '\r\033[KJobID %s | JobPriority %s | JobName %s | GridUser %s | JobStatus %s | SubmitTime %s | RunningOn %s | Slots %s' $(qstat -xml | sed 's#<job_list[^>]*># #g' | sed 's#<[^>]*>##g')
		clear
		printf '\r\033[K%s' ${GREY}
		qstat -f -q ${queue}
		printf '%s\r\033[K' ${NC}		
	done
	# proceed only if required files exist
	[ ! -f "${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz" ] && echo -e "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} missing ${subject}/mri/brainmask.mgz - did recon-all fail?" && return 1
	##################################################		
	## 	2 --> convert brainmask to NIFTI
	##################################################
	[ ! -d "${SUBJECTS_DIR}/${subject}/qc/" ] && mkdir -v "${SUBJECTS_DIR}/${subject}/qc/"
	if mri_convert "${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz" "${SUBJECTS_DIR}/${subject}/qc/brainmask.nii.gz" >&3; then
		>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} mri_convert ${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz ${SUBJECTS_DIR}/${subject}/qc/brainmask.nii.gz"
	else
		>&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} mri_convert ${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz ${SUBJECTS_DIR}/${subject}/qc/brainmask.nii.gz"
		return 1
	fi
	##################################################		
	## 	3 --> threshold edits out (eraser value = 1)
	##################################################
	if fslmaths "${SUBJECTS_DIR}/${subject}/qc/brainmask.nii.gz" -thr 2 "${SUBJECTS_DIR}/${subject}/qc/brainmask_clean.nii.gz" >&3; then
		>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} fslmaths ${SUBJECTS_DIR}/${subject}/qc/brainmask.nii.gz -thr 2 ${SUBJECTS_DIR}/${subject}/qc/brainmask_clean.nii.gz"
	else
		>&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} fslmaths ${SUBJECTS_DIR}/${subject}/qc/brainmask.nii.gz -thr 2 ${SUBJECTS_DIR}/${subject}/qc/brainmask_clean.nii.gz"
		return 1
	fi
	##################################################		
	## 	4 --> warp edit-free brainmasks to template  
	##################################################	
	# TODO test
	# TODO add overwrite check logic
	local sstname=$(echo ${sst} | sed 's|/| |g' | awk '{print $NF}' | sed 's|.nii.gz||g')
	local command="${ANTSPATH}/antsIntroduction.sh -d 3 -i ${SUBJECTS_DIR}/${subject}/qc/brainmask_clean.nii.gz -r ${sst} -m 30x75x45x40x25x10 -n 0 -t GR -o ${SUBJECTS_DIR}/${subject}/qc/${subject}_${sstname}_"
	if [ ! -f "${SUBJECTS_DIR}/${subject}/qc/${subject}_${sstname}_deformed.nii.gz" ]; then
		if preproc_make_job "${SUBJECTS_DIR}"/sgeworkdir ${subject} 'antswarp' ${queue} ${command}; then
			>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} preproc_make_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'antswarp' ${queue} ${command}"
		else
			>&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} preproc_make_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'antswarp' ${queue} ${command}"		
			return 1
		fi
		if preproc_submit_job "${SUBJECTS_DIR}"/sgeworkdir ${subject} 'antswarp'; then
			printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} preproc_submit_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'antswarp'"
		else
			>&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} preproc_submit_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'antswarp'"		
			return 1
		fi
	else
		printf '\r033[K${BLUE} File Exists ${NC}:: %s' "${SUBJECTS_DIR}"/"${subject}"/qc/"${subject}"_"${sstname}"_deformed.nii.gz
		if [ "${overwrite}" ]; then
			printf '\r033[K${YELLOW} Overwriting ${NC}:: %s' "${SUBJECTS_DIR}"/"${subject}"/qc/"${subject}"_"${sstname}"_deformed.nii.gz
			if preproc_make_job "${SUBJECTS_DIR}"/sgeworkdir ${subject} 'antswarp' ${queue} ${command}; then
				>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} preproc_make_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'antswarp' ${queue} ${command}"
			else
				>&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} preproc_make_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'antswarp' ${queue} ${command}"		
				return 1
			fi
			if preproc_submit_job "${SUBJECTS_DIR}"/sgeworkdir ${subject} 'antswarp'; then
				printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} preproc_submit_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'antswarp'"
			else
				>&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} preproc_submit_job ${SUBJECTS_DIR}/sgeworkdir ${subject} 'antswarp'"		
				return 1
			fi			
		fi
	fi	
	# wait for job to finish	
	while [ "$(echo -e $(qstat -xml | sed 's#<job_list[^>]*>#\\n#g' | sed 's#<[^>]*>##g') | grep "antswarp-${subject}")" ]; do
		clear
		printf '\r\033[K%s' ${GREY}
		qstat -f -q ${queue}
		printf '%s\r\033[K' ${NC}		
		#>&3 printf '\r\033[KJobID %s\nJobPriority %s\nJobName %s\nGridUser %s\nJobStatus %s\nSubmitTime %s\nRunningOn %s\nSlots %s' $(qstat -xml | sed 's#<job_list[^>]*># #g' | sed 's#<[^>]*>##g') | column -t
	done
	##################################################		
	## 	5 --> binarize warped brainmasks
	##################################################		
	if fslmaths "${SUBJECTS_DIR}"/${subject}/qc/${subject}_${sstname}_deformed.nii.gz -bin "${SUBJECTS_DIR}"/${subject}_brainmask_cleaned_${sstname}_deformed_binarized.nii.gz >&3; then
		>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} ${SUBJECTS_DIR}/${subject}/qc/${subject}_${sstname}_deformed.nii.gz -bin ${SUBJECTS_DIR}/${subject}_brainmask_cleaned_${sstname}_deformed_binarized.nii.gz"
	else
		>&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} ${SUBJECTS_DIR}/${subject}/qc/${subject}_${sstname}_deformed.nii.gz -bin ${SUBJECTS_DIR}/${subject}_brainmask_cleaned_${sstname}_deformed_binarized.nii.gz"
		return 1
	fi
	## return with clean no-error code if you get to this point!
	return 0
}
export -f preproc_structural_brainmask_prob_subject
############################################################################################################################################
# --------------------------------------------> 											   Preprocess | T1w | Brain Mask | Probabilistic
############################################################################################################################################
# TODO testing
# TODO brain extraction with specific modality SST?
function preproc_structural_brainmask_prob(){
	SUBJECTS_DIR="${1}" && export SUBJECTS_DIR && shift
	local sstname="${1}" && shift
	local OUTDIR="${1}" && shift
	local INDIR="${1}" && shift
	local modality="${@}"
	##################################################		
	## 	0 --> defaults
	##################################################			
	# the default modality is the first one in the list (be careful!)
	local defmod=$(echo ${modality} | awk '{print $1}')
	local sstprior="${OUTDIR}"/"${sstname}${defmod}"-sst_brainmask-prior.nii.gz
	local sstbm="${OUTDIR}"/"${sstname}${defmod}"-sst_brain.nii.gz					
	local sst="${INDIR}"/"${sstname}${defmod}"-sst.nii.gz			
	[ ! -d "${OUTDIR}" ] && mkdir -pv "${OUTDIR}"
	##################################################		
	## 	1 --> add across participants in sst space
	##################################################		
	if fsladd "${INDIR}"/"${sstname}${defmod}"-sst_brainmask-sum.nii.gz "$(find "${SUBJECTS_DIR}" -name "*_brainmask_cleaned_"${sstname}"deformed_binarized.nii.gz")" >&3; then
		>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} fsladd ${INDIR}/${sstname}${defmod}-sst_brainmask-sum.nii.gz $(find "${SUBJECTS_DIR}" -name "*_brainmask_cleaned"${sstname}"deformed_binarized.nii.gz")\n"
	else
		>&2 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} fsladd ${INDIR}/${sstname}${defmod}-sst_brainmask-sum.nii.gz $(find "${SUBJECTS_DIR}" -name "*_brainmask_cleaned_"${sstname}"deformed_binarized.nii.gz")\n"
		return 1
	fi
	##################################################		
	## 	2 --> compute probability map
	##################################################
	local numsub=$(find "${SUBJECTS_DIR}" -name "*_brainmask_cleaned_"${sstname}"deformed_binarized.nii.gz" | wc -l)
	if fslmaths "${INDIR}"/"${sstname}${defmod}"-sst_brainmask-sum.nii.gz -div "${numsub}" "${INDIR}"/"${sstname}${defmod}-sst_"brainmask-prior.nii.gz >&3; then
		>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} fslmaths ${INDIR}/${sstname}${defmod}-sst_brainmask-sum.nii.gz -div ${numsub} ${INDIR}/${sstname}${defmod}-sst_brainmask-prior.nii.gz\n"
	else
		>&2 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} fslmaths ${INDIR}/${sstname}${defmod}-sst_brainmask-sum.nii.gz -div ${numsub} ${INDIR}/${sstname}${defmod}-sst_brainmask-prior.nii.gz\n"
		return 1
	fi
	# smooth probability map with Gaussian (width = 1 stdev)
	cp -v "${INDIR}"/"${sstname}${defmod}"-sst_brainmask-prior.nii.gz "${INDIR}"/"${sstname}${defmod}"-sst_brainmask-prior_orig.nii.gz
	if ${ANTSPATH}/ImageMath 3 "${INDIR}"/"${sstname}${defmod}"-sst_brainmask-prior.nii.gz G "${INDIR}"/"${sstname}${defmod}"-sst_brainmask-prior.nii.gz 1 >&3; then
		>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} ${ANTSPATH}/ImageMath 3 ${INDIR}/${sstname}${defmod}-sst_brainmask-prior.nii.gz G ${INDIR}/${sstname}${defmod}-sst_brainmask-prior.nii.gz 1\n"
	else
		>&2 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} ${ANTSPATH}/ImageMath 3 ${INDIR}/${sstname}${defmod}-sst_brainmask-prior.nii.gz G ${INDIR}/${sstname}${defmod}-sst_brainmask-prior.nii.gz 1\n"
		return 1
	fi
	cp -v "${INDIR}"/"${sstname}${defmod}"-sst_brainmask-prior.nii.gz "${sstprior}"
	# !! inspect image and manually clean up if needed
	# TODO continue on user input	
	##################################################		
	## 	3 --> brain extract template
	##################################################
	if ${ANTSPATH}/antsBrainExtraction.sh -d 3 -k 1 -a "${sst}" -e "${sst}" -m "${sstprior}" -o "${OUTDIR}"/"${sstname}ANTSBEX-" >&3; then
		>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} ${ANTSPATH}/antsBrainExtraction.sh -d 3 -k 1 -a ${sst} -e ${sst} -m ${sstprior} -o ${OUTDIR}/${sstname}ANTSBEX-"
	else
		>&2 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} ${ANTSPATH}/antsBrainExtraction.sh -d 3 -k 1 -a ${sst} -e ${sst} -m ${sstprior} -o ${OUTDIR}/${sstname}ANTSBEX-"
		return 1
	fi
	cp -v "${OUTDIR}"/"${sstname}ANTSBEX-BrainExtractionBrain.nii.gz" "${sstbm}"
	##################################################		
	## 	4 --> template-based extraction using pmap
	##################################################
	# loop across all denoised data
	for f in $(find ${INDIR}/ -name '*_N4_RicianDenoised.nii.gz'); do
		local subject=$(echo "${f}" | grep -oE 'sub-[0-9]{3,4}_ses-wave[0-9]_run-[0-9][1-9]' | sort -u)
		# build brain extraction command based on modality
		if echo "${f}" | grep 'T1w'; then
			local command="antsBrainExtraction.sh -d 3 -k 1 -a "${f}" -e "${sstbm}" -m "${sstprior}" -c 3x1x2x3 -o "${OUTDIR}"/"${subject}"_T1w_N4_RicianDenoised_ANTSBEX-"
		elif echo "${f}" | grep 'T2w'; then
			local command="antsBrainExtraction.sh -d 3 -k 1 -a "${f}" -e "${sstbm}" -m "${sstprior}" -c 3x3x2x1 -o "${OUTDIR}"/"${subject}"_T2w_N4_RicianDenoised_ANTSBEX-"
		else
			>&3 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} Unknown Modality for ${f} - cannot perform segmentation for brain extraction, exiting\n"
			return 1			
		fi
		# create job submission scripts
		if preproc_make_job "${OUTDIR}" "${subject}" 'abex' "${queue}" "${command}"; then
			>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} preproc_make_job ${OUTDIR} ${subject} 'abex' ${queue} ${command}\n"
		else
			>&2 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} preproc_make_job ${OUTDIR} ${subject} 'abex' ${queue} ${command}\n"
			return 1
		fi
		# submit jobs to grid
		if preproc_submit_job "${OUTDIR}" "${subject}" 'abex'; then
			>&3 printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} preproc_submit_job ${OUTDIR} ${subject} 'abex'"
		else
			>&2 printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} preproc_submit_job ${OUTDIR} ${subject} 'abex'"
			return 1
		fi
	done		
	return 0
}
export -f preproc_structural_brainmask_prob
############################################################################################################################################
# --------------------------------------------> 																  	 Preprocess | Structural
############################################################################################################################################
# Main Function for Preprocessing Structural Data
# TODO input/output redirection
# ERROR control flow (run each command as a test)
# TODO check for structural modalities (T1w is crucial no?)
#
# This function creates a minimally-preprocessed folder containing the following:
#
# * Minimally Processed Data
#		minimally-preprocessed/sub-*_ses-*_run-*_${modality}_N4.nii.gz
#		minimally-preprocessed/sub-*_ses-*_run-*_${modality}_N4BiasField.nii.gz
#		minimally-preprocessed/sub-*_ses-*_run-*_${modality}_N4_RicianDenoised.nii.gz
#		minimally-preprocessed/sub-*_ses-*_run-*_${modality}_N4_RicianEstmNoise.nii.gz
#		minimally-preprocessed/${SSTNAME}_sst-${modality}
#		minimally-preprocessed/${SSTNAME}_sst-${modality}_mni-rr_
#		TODO minimally-preprocessed/antsbrainmasked
#		TODO minimally-preprocessed/warped-to-template
#		TODO minimally-preprocessed/gray,white,csf,cortex,subcortical tpms and masks
#		TODO minimally-preprocessed/subcortical ROIs
#
# * Multi-Contrast Study Specific Template
#		sst/
#		sst/recons
#
#   A study specific template is created using the specified sessions in ${SSTCOV}.
#   This includes warps from each session to the template. The user can specify the
#   modalities (T1w/T2w) to create templates for. FreeSurfer reconstruction is run
#	on all participants in template space. An average subject surface is created
#	using FreeSurfer make_average_subject.
#
# * Watershed + Template Based Skull Stripping
#
# * FreeSurfer Reconstructions 
#		recons/sub-*_ses-*_run-*.nii.gz
#		TODO register all subjects to study specific template
#		TODO sample glasser atlas from fsaverage to study specific template

function preproc_structural(){
	local WORKDIR=${1}
	local workdir=${WORKDIR}/minimally-preprocessed && [ ! -d "${workdir}" ] && mkdir -pv "${workdir}"
	##########################################################################
	# 1] Loop over Structural Modalities & Denoise
	##########################################################################
	# Default Denoising Model is Rician (defined in function)
	for modality_struct in "${MODALITY_STRUCT[@]}"; do
		if echo "${PARALLELOPT}" | grep -- "-S " > /dev/null; then
			printf "${BLUE} NLM + N4 Denoising for ${YELLOW}${modality_struct}${NC} (GNU Parallel on Network)\n"
			## process over network
			source `which env_parallel.bash`
			## check for existence of modality in data manifest
			if tail -n +2 "${DATAMANIFEST}" | grep "${modality_struct}" > /dev/null; then
				(if env_parallel -k --link --bar "${PARALLELOPT}" preproc_structural_denoise "${SOURCEDATA}"/{} "${workdir}" ${OVERWRITE}\
						::: $(tail -n +2 "${DATAMANIFEST}" | grep "${modality_struct}" \
						| awk -v var="${modality_struct}" '{ printf "%s/%s/anat/%s_%s_run-0%s_%s.nii.gz\n", $1,$2,$1,$2,$3,var}') \
					1>> "${LOGOUT}" 2>>"${LOGERR}"; then
					printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${GREY} env_parallel -k --link ${PARALLELOPT} preproc_structural_denoise ${SOURCEDATA}/{} ${workdir} ${OVERWRITE} ::: $(tail -n +2 "${DATAMANIFEST}" | grep "${modality_struct}" | awk -v var=${modality_struct} '{ printf "%s/%s/anat/%s_%s_run-0%s_%s.nii.gz ", $1,$2,$1,$2,$3,var}') ${NC}"
					printf "${GREEN}==========================================================================================\n${NC}"
					echo '' > /tmp/main_return_val
				else
					printf "\r\033[K${BRED}◀︎|⁃‣ERROR${GREY} env_parallel -k --link ${PARALLELOPT} preproc_structural_denoise ${SOURCEDATA}/{} ${workdir} ${OVERWRITE} ::: $(tail -n +2 "${DATAMANIFEST}" | grep "${modality_struct}" | awk -v var=${modality_struct} '{ printf "%s/%s/anat/%s_%s_run-0%s_%s.nii.gz ", $1,$2,$1,$2,$3,var}') ${NC}"
					echo 'return 1' > /tmp/main_return_val
				fi | tee -a "${LOGOUT}") 1>&2 | tee -a "${LOGERR}"						
			else
				printf "\r\033[K${YELLOW}Warning ${GREY}${modality_struct} Images Not Found in Data Manifest${NC}"
			fi
		else
			## local processing
			## check for existence of modality in data manifest
			if tail -n +2 "${DATAMANIFEST}" | grep "${modality_struct}" > /dev/null; then
				printf "${BLUE} NLM + N4 Denoising for ${YELLOW}${modality_struct}${NC} (GNU Parallel)\n"
				(if parallel -k --link preproc_structural_denoise "${SOURCEDATA}"/{} "${workdir}" ${OVERWRITE}\
						::: $(tail -n +2 "${DATAMANIFEST}" | grep "${modality_struct}" \
							| awk -v var="${modality_struct}" '{ printf "%s/%s/anat/%s_%s_run-0%s_%s.nii.gz\n", $1,$2,$1,$2,$3,var}') \
						1>> "${LOGOUT}" 2>>"${LOGERR}"; then
					printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${GREY} parallel -k --link preproc_structural_denoise ${SOURCEDATA}/{} ${workdir} ::: $(tail -n +2 "${DATAMANIFEST}" | grep "${modality_struct}" | awk -v var=${modality_struct} '{ printf "%s/%s/anat/%s_%s_run-0%s_%s.nii.gz ", $1,$2,$1,$2,$3,var}') ${NC}"
					printf "\n${GREEN}==========================================================================================\n${NC}"
					echo '' > /tmp/main_return_val
				else
					printf "\r\033[K${BRED}◀︎|⁃‣ERROR${GREY} parallel -k --link preproc_structural_denoise ${SOURCEDATA}/{} ${workdir} ::: $(tail -n +2 "${DATAMANIFEST}" | grep "${modality_struct}" | awk -v var=${modality_struct} '{ printf "%s/%s/anat/%s_%s_run-0%s_%s.nii.gz ", $1,$2,$1,$2,$3,var}') ${NC}"
					echo 'return 1' > /tmp/main_return_val
				fi | tee -a "${LOGOUT}") 3>&1 1>&2 2>&3 | tee -a "${LOGERR}"
			else
				printf "\r\033[K${YELLOW}Warning ${GREY}${modality_struct} Images Not Found in Data Manifest${NC}"
			fi
		fi
	done	
	##########################################################################
	# 2] Create Study Specific Template with Denoised Images
	##########################################################################
	printf "${BLUE} Study Specific Template Construction for ${YELLOW}${MODALITY_STRUCT[@]}${NC}\n"	
	OVERWRITE=''
	workdir=${WORKDIR}/sst && [ ! -d "${workdir}" ] && mkdir -pv "${workdir}"
	local sstname="$(echo ${SSTNAME}_$(printf "%s_" "${MODALITY_STRUCT[@]}"))"
	## -- only update SST if user specifies overwrite
	if [ "$(find "${workdir}"/ -name "${sstname}template[0-9].nii.gz")" ]; then
		printf "${BLUE} --> SST Exists ${GREY}${workdir}/${sstname}template[1-9].nii.gz${NC}\n"
		# -- check whether user wants overwrite
		if [ "${OVERWRITE}" ]; then
			printf "${BLUE} --> Overwriting SST ${YELLOW}${workdir}/${sstname}sst-*.nii.gz${NC}\n"
			(if preproc_structural_ants_sst "${sstname}" "${WORKDIR}/minimally-preprocessed" "${workdir}" "${MODALITY_STRUCT[@]}" 2>>"${LOGERR}" 1>>"${LOGOUT}"; then
				printf "\r\033[f${GREEN}◀︎|⁃‣SUCCESS${NC} preproc_structural_ants_sst ${sstname} ${WORKDIR}/minimally-preprocessed ${workdir} ${MODALITY_STRUCT[@]}\n"
				for m in ${MODALITY_STRUCT[@]}; do
					cp -v "${workdir}"/"${sstname}"sst-"${m}".nii.gz "${WORKDIR}"/minimally-preprocessed/
					cp -v "${workdir}"/"${sstname}"sst-"${m}"_mni-rr_*.nii.gz "${WORKDIR}"/minimally-preprocessed/
				done
				echo '' > /tmp/main_return_val
			else
				printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} preproc_structural_ants_sst ${sstname} ${WORKDIR}/minimally-preprocessed ${workdir} ${MODALITY_STRUCT[@]}\n"
				echo 'return 1' > /tmp/main_return_val
			fi | tee -a "${LOGOUT}") 3>&1 1>&2 2>&3 | tee -a "${LOGERR}" && eval "$(cat /tmp/main_return_val)"
		fi
	else
		## -- create specified SST if doesn't exist
		printf "${BLUE} --> Creating SST ${GREY}${workdir}/${sstname}sst.nii.gz${NC}"
		(if preproc_structural_ants_sst "${sstname}" "${WORKDIR}/minimally-preprocessed" "${workdir}" "${MODALITY_STRUCT[@]}" 2>>"${LOGERR}" 1>>"${LOGOUT}"; then
			printf "\r\033[${GREEN}◀︎|⁃‣SUCCESS${NC} preproc_structural_ants_sst ${sstname} ${WORKDIR}/minimally-preprocessed ${workdir} ${MODALITY_STRUCT[@]}"
			for m in ${MODALITY_STRUCT[@]}; do
				cp -v "${workdir}"/"${sstname}"sst-${m}.nii.gz "${WORKDIR}"/minimally-preprocessed/
				cp -v "${workdir}"/"${sstname}"sst-${m}_mni-rr_*.nii.gz "${WORKDIR}"/minimally-preprocessed/
			done
			echo '' > /tmp/main_return_val
		else
			printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} preproc_structural_ants_sst ${sstname} ${WORKDIR}/minimally-preprocessed ${workdir} ${MODALITY_STRUCT[@]}\n"
			echo 'return 1' > /tmp/main_return_val
		fi | tee -a "${LOGOUT}") 3>&1 1>&2 2>&3 | tee -a "${LOGERR}" && eval "$(cat /tmp/main_return_val)"
	fi
	##########################################################################
	# 3] Study Specific Template FreeSurfer Average
	##########################################################################		
		# Run freesurfer on all subjects used to create SST
		# --> run full pipeline on transformed files
		# --> note that multiple modalities are checked for automatically 
		# --> create average subject
		# --> register all individual subjects to average
		## -- create specified SST if doesn't exist
	printf "${BLUE} --> SST Cortical Surface Reconstruction ${NC}\n"		
	(if preproc_structural_ants_sst_freesurfer "${workdir}" "${BIDSDIR}" "${QUEUE}" "${sstname}" "${overwrite}"; then
		printf "\r\033[${GREEN}◀︎|⁃‣SUCCESS${NC} preproc_structural_ants_sst_freesurfer ${workdir} ${BIDSDIR} ${QUEUE} ${sstname} ${overwrite}"
		echo '' > /tmp/main_return_val
	else
	 	printf "\r\033[${BRED}◀︎|⁃‣ERROR${NC} preproc_structural_ants_sst_freesurfer ${workdir} ${BIDSDIR} ${QUEUE} ${sstname} ${overwrite}"
	 	echo 'return 1' > /tmp/main_return_val
	fi | tee -a "${LOGOUT}") 3>&1 1>&2 2>&3 | tee -a "${LOGERR}" && eval "$(cat /tmp/main_return_val)"
	##########################################################################
	# 4] Brain Extraction with Watershed x Template Based Skull-Stripping
	##########################################################################	
	## -- watershed skull-stripping algorithm using freesurfer
	local sourcedata=${WORKDIR}/minimally-preprocessed
	local sst_t1w=${sourcedata}/${sstname}sst-T1w.nii.gz
	workdir=${WORKDIR}/recons && [ ! -d "${workdir}" ] && mkdir -pv "${workdir}"
	(if parallel -k --link preproc_structural_brainmask_prob_subject "${sourcedata}" {} "${BIDSDIR}" "${workdir}" "${sst_t1w}" "${QUEUE}" "${OVERWRITE}" ::: $(find "${sourcedata}" -name '*_T1w_N4_RicianDenoised.nii.gz' | grep -oE 'sub-[0-9]{3,4}_ses-wave[0-9]_run-0[1-9]'); then
		printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} parallel -k --link preproc_structural_brainmask_prob_subject ${sourcedata} {} ${BIDSDIR} ${workdir} ${sst_t1w} ${QUEUE} ${OVERWRITE} ::: $(printf '%s ' $(find ${sourcedata} -name '*_T1w_N4_RicianDenoised.nii.gz' | grep -oE 'sub-[0-9]{3,4}_ses-wave[0-9]_run-0[1-9]'))"		
		echo '' > /tmp/main_return_val
	else
		printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} parallel -k --link preproc_structural_brainmask_prob_subject ${sourcedata} {} ${BIDSDIR} ${workdir} ${sst_t1w} ${QUEUE} ${OVERWRITE} ::: $(printf '%s ' $(find ${sourcedata} -name '*_T1w_N4_RicianDenoised.nii.gz' | grep -oE 'sub-[0-9]{3,4}_ses-wave[0-9]_run-0[1-9]'))"				
		echo 'return 1' > /tmp/main_return_val		
	fi | tee -a "${LOGOUT}") 3>&1 1>&2 2>&3 | tee -a "${LOGERR}" && eval "$(cat /tmp/main_return_val)"	
	## -- template based brain extraction with probabilstic mask
	# TODO test
	(if preproc_structural_brainmask_prob "${workdir}" "${sstname}" "${sourcedata}" "${sourcedata}" "${MODALITY_STRUCT}" 2>>"${LOGERR}" 1>>"${LOGOUT}"; then
		printf "\r\033[K${GREEN}◀︎|⁃‣SUCCESS${NC} preproc_structural_brainmask_prob ${workdir} ${sstname} ${sourcedata} ${sourcedata} ${MODALITY_STRUCT}"
		echo '' > /tmp/main_return_val
	else
		printf "\r\033[K${BRED}◀︎|⁃‣ERROR${NC} preproc_structural_brainmask_prob ${workdir} ${sstname} ${sourcedata} ${sourcedata} ${MODALITY_STRUCT}"
		echo 'return 1' > /tmp/main_return_val
	fi | tee -a "${LOGOUT}") 3>&1 1>&2 2>&3 | tee -a "${LOGERR}" && eval "$(cat /tmp/main_return_val)"
	# TODO copy brain extractions and masks to minimally-preprocessed workdir

	##########################################################################
	# 5] FreeSurfer Reconstruction with Updated Brainmasks
	##########################################################################		
	# ------> copy ants bex to freesurfer directory
	# ------> run complete freesurfer reconstruction pipeline for all subjects

	##########################################################################
	# 6] Segmentation + Labeling
	##########################################################################		
		# OASIS 6 Class Tissue Segmentation
		# CITI Reinforcement Learning Atlas Segmentation
		# Fuse labels from FreeSurfer

	##########################################################################
	# 7] Warp to Study Specific Template Space
	##########################################################################		
	# ------> warp individual subjects to study specific template

	##########################################################################
	# x] ANTs Cortical Thickness ?
	##########################################################################		

	###### --> DONE
	# If you got this far then exist with a clean no-error signal! Great job!	
	##### ---> DONE
	return 0
}
############################################################################################################################################
# --------------------------------------------> 												   				  Preprocess | bold | unwarp
############################################################################################################################################
# TODO
function preproc_bold_unwarp_blipupd(){
	# merge bliup up and blip down files
	# create acquisition parameters text file with rows in same order of merge
	# file 1: x y z TRT
	# file 2: x y z TRT
	# where: 0 -1 0 is A>>P (blip up)
	#		 0  1 0 is P>>A (blip down)
	echo wip
}
############################################################################################################################################
# --------------------------------------------> 												   Preprocess | bold | rest | single subject
############################################################################################################################################
# Main Function for Preprocessing Bold Resting State Data
# TODO
function preproc_bold_rest_subject(){
	INDIR=${1}
	OUTDIR=${2}
	###
	for f in ${T1ws}; do
		FILES+=$(echo $(find ${INDIR} -name ${f})" ")
	done
	# unwarp
	preproc_bold_unwarp_blipupd
	# N4 correct
	# IMAGES=$(find ${WORKDIR} -name '*bold_mcflirt_stc.nii.wgz')	
	# ${ANTSBIN}/N4BiasFieldCorrection -d 4 -i {1} -o [${WORKDIR}/{2}_mcflirt_stc_N4.nii.gz,${WORKDIR}/{2}_mcflirt_stc_biasField.nii.gz] ::: ${IMAGES} ::: ${SUBJECTS}	
	# align
	#${FSLDIR}/bin/mcflirt -in ${SOURCEDATA}/{}.nii.gz -out ${WORKDIR}/{}_mcflirt -stats -plots -refvol 5 ${SUBJECTS}
	# slice time correct
	#${FSLDIR}/bin/slicetimer -i ${WORKDIR}/{}_mcflirt.nii.gz -o ${WORKDIR}/{}_mcflirt_stc.nii.gz -r 2.28 --odd ::: ${SUBJECTS}
	# calc descriptive stats for stc 
	IMAGES=$(find ${WORKDIR} -name '*bold_mcflirt_stc.nii.gz')	
	#fslmaths {1} -Tmean ${WORKDIR}/{2}_mcflirt_stc_mean ::: ${IMAGES} ::: ${SUBJECTS}
	#fslmaths {1} -Tstd ${WORKDIR}/{2}_mcflirt_stc_std ::: ${IMAGES} ::: ${SUBJECTS}		
	# calc descriptive stats for stc + N4
	IMAGES=$(find ${WORKDIR} -name '*bold_mcflirt_stc_N4.nii.gz')	
	#fslmaths {1} -Tmean ${WORKDIR}/{2}_mcflirt_stc_N4_mean ::: ${IMAGES} ::: ${SUBJECTS}
	#fslmaths {1} -Tstd ${WORKDIR}/{2}_mcflirt_stc_N4_std ::: ${IMAGES} ::: ${SUBJECTS}		
	# tSNR for non-N4 images
	MEANEPIs=$(find ${WORKDIR} -name '*bold_mcflirt_stc_mean.nii.gz')
	STDEPIs=$(find ${WORKDIR} -name '*bold_mcflirt_stc_std.nii.gz')
	#fslmaths {1} -div {2} ${WORKDIR}/{3}_mcflirt_stc_tsnr ${MEANEPIs} ::: ${STDEPIs} ::: ${SUBJECTS}
	# tSNR for N4 corrected images
	MEANEPIs=$(find ${WORKDIR} -name '*bold_mcflirt_stc_N4_mean.nii.gz')
	STDEPIs=$(find ${WORKDIR} -name '*bold_mcflirt_stc_N4_std.nii.gz')
	#fslmaths {1} -div {2} ${WORKDIR}/{3}_mcflirt_stc_N4_tsnr ${MEANEPIs} ::: ${STDEPIs} ::: ${SUBJECTS}
	# brainmask
	# denoise images
	# warp to ads56 space	
}
############################################################################################################################################
# --------------------------------------------> 																  	Preprocess | bold | rest
############################################################################################################################################
# Main Function for Preprocessing Bold Resting State Data
function preproc_bold_rest(){
	WORKDIR=${1}
	workdir="${WORKDIR}"/minimally-preprocessed && [ ! -d "${workdir}" ] && mkdir -pv "${workdir}"
	EPIs=$(tail -n +2 "${DATAMANIFEST}" | grep 'rest' | grep 'bold' | awk '{ printf "%s_ses-wave%s_run-0%s_bold.nii.gz\n", $1,$2,$3}')	
	# run in parallel
	preproc_bold_rest_subject ${SOURCEDATA} ${workdir}
	return 0
}
############################################################################################################################################
# --------------------------------------------> 														   Preprocess | dwi | single subject
############################################################################################################################################
# Main Function for Preprocessing Bold Resting State Data
function preproc_dwi_subject(){
	echo wip
}
############################################################################################################################################
# --------------------------------------------> 																  			Preprocess | dwi
############################################################################################################################################
# Main Function for Preprocessing Bold Resting State Data
function preproc_dwi(){
	echo wip
}
############################################################################################################################################
# --------------------------------------------> 																  				  Preprocess
############################################################################################################################################
function preproc(){
	echo wip
}
############################################################################################################################################
# --------------------------------------------> 																  						Main
############################################################################################################################################
clear
declare_defaults
preproc_structural "${WORKDIR}"
