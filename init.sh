#!/bin/bash

## TODO function to check for dependencies 


############################################################################################################################################
# --------------------------------------------> 																			   Parse Options
############################################################################################################################################
function parseOpts(){
	while (( "$#" )); do
	    case ${1} in
	    -d|--dir)
			DATASET_DIR=${2}
			export DATASET_DIR
			shift
			;;	    	
	    -s|--data-source)
			DATASET_SOURCE_DICOM_DIR=${2}
			export DATASET_SOURCE_DICOM_DIR
			shift
			;;
		--help|-help|-h|help)
			HELP='more'
			init_usage
			exit
			;;
		*)
		    printf '\n'${YELLOW}' Warning: '${NC}'Unknown option: "%s"\n' "${1}" >&2
		  	;;
	    esac
	    shift
	done
}
export -f parseOpts
############################################################################################################################################
# --------------------------------------------> 																	   Initialize | Defaults
############################################################################################################################################
function initialize_defaults(){
	find /tmp/ -name 'init*' -exec rm -v {} \; 2>/dev/null 1>/dev/null
	####################################################################################################################	
	TEMPLATE_URL="https://github.com/seldamat/mrinit_dataset_template.git"
	####################################################################################################################	
	# static parameters :: formatting
	####################################################################################################################	
	export RED='\033[0;31m' && export BRED='\033[1;31m'
	export YELLOW='\033[1;33m' && export GREEN='\033[1;32m'
	export BLUE='\033[1;34m' && export GREY='\033[1;37m'
	export NC='\033[0m' && export BBLUE='\033[1;40m'
	export NBC='\033[49m' && export GGREY='\033[1;30m'
	export YBC='\033[47m' && export LRED='\033[1;31m'	
	####################################################################################################################	
	# static parameters :: logging
	####################################################################################################################	
	LOG="/tmp/init.runtime.$$"
	export LOGOUT=${LOG}.out && export LOGERR=${LOG}.err
	export BIDS_DICOM_KEYS="AcquisitionMatrix AcquisitionMatrixPE AcquisitionNumber AcquisitionTime AnatomicalLandmarkCoordinates BaseResolution CoilCombinationMethod CoilString ConversionSoftware ConversionSoftwareVersion DeviceSerialNumber DwellTime EchoTime EffectiveEchoSpacing FlipAngle GradientSetType ImageOrientationPatientDICOM ImageType ImagingFrequency InPlanePhaseEncodingDirectionDICOM InstanceCreationTime InstitutionAddress InstitutionName InstitutionalDepartmentName InversionTime MagneticFieldStrength Manufacturer ManufacturersModelName MatrixCoilMode Modality MRAcquisitionType MRTransmitCoilSequence MultibandAccelerationFactor NegativeContrast NonlinearGradientCorrection NumberofAverages NumberofPhaseEncodingSteps NumberShots ParallelAcquisitionTechnique ParallelReductionFactorInPlane PartialFourier PartialFourierDirection PatientBirthDate PatientID PatientName PatientPosition PatientSex PatientWeight PercentPhaseFieldOfView PerformedProcedureStepStartTime PhaseEncodingDirection PhaseEncodingSteps PhaseOversampling PhaseResolution PixelBandwidth PixelSpacing ProcedureStepDescription ProtocolName PulseSequenceDetails PulseSequenceType ReceiveCoilActiveElements ReceiveCoilName ReconMatrixPE RepetitionTime SAR ScanOptions ScanningSequence SequenceName SequenceVariant SeriesDescription SeriesNumber ShimSetting SliceEncodingDirection SliceThickness SliceTiming SoftwareVersions StationName StudyDescription TotalReadoutTime TxRefAmp"
	export OVERWRITE=''
	export SOURCE_CONFIG="${DATASET_DIR}"/data/source/mri/dataset_config.json
}
export -f initialize_defaults
############################################################################################################################################
# --------------------------------------------> 																 Initialize | Parent Dataset
############################################################################################################################################
function initialize_dataset(){
	local dir=${1} && shift
	local name=${1} && shift
	local dataset_dir=${dir}/${name}
	############################################################################################
	# Create Versioned Dataset
	############################################################################################
	if datalad install -r -s ${TEMPLATE_URL} "${dataset_dir}"; then
		echo -e "${GREEN} Dataset Initialized with Template (${TEMPLATE_URL})${NC}"
	else
		echo -e "${YELLOW} Cannot Contact Remote (${TEMPLATE_URL}) ${BLUE}- initializing locally${NC}"
		datalad create -D "Dataset Template" "${dataset_dir}"
		initialize_dataset_tree "-d ${dataset_dir}"
	fi
	############################################################################################
	# done!
	return 0
}
export -f initialize_dataset
############################################################################################################################################
# --------------------------------------------> 															    Initialize | Publish DataSet
############################################################################################################################################
# todo allow dataset to publish to link with doi (add to JSON)
function initialize_dataset_publish(){
	datalad publish -d $(pwd) -r --to github data	
}
############################################################################################################################################
# --------------------------------------------> 																   Initialize | Sub-Datasets
############################################################################################################################################
# TODO ! git submodule entry
#		 submodule needs to be updated within each subdataset container
function initialize_dataset_tree(){
	local opts="$@"
	############################################################################################
	# Code
	############################################################################################
	datalad create ${opts} -D 'Dataset Template :: Code' code
	############################################################################################
	# Data
	############################################################################################	
	datalad create ${opts} -D 'Dataset Template :: Data' data
	############################################################################################
	# BIDS
	############################################################################################	
	datalad create ${opts} -D 'Dataset Template :: BIDS Format Data' data/bids
	# TODO add files needed for BIDS format
	############################################################################################
	# Source Data Container
	############################################################################################
	datalad create ${opts} -D 'Dataset Template :: Raw Source Data' data/source
	############################################################################################
	# MRI Source Data
	############################################################################################
	datalad create ${opts} -D 'Dataset Template :: MRI Source Data' data/source/mri
	printf 'Dataset Custom Configuration\n' > ${dataset_dir}/data/source/mri/dataset_config.tsv
	printf 'Dataset Name\tDefault Name\n' >> ${dataset_dir}/data/source/mri/dataset_config.tsv
	printf 'Dataset Description\tDefault Template Description\n' >> ${dataset_dir}/data/source/mri/dataset_config.tsv
	printf 'Dataset Path\tDefault Path\n' >> ${dataset_dir}/data/source/mri/dataset_config.tsv
	############################################################################################
	# Source Behavior Data
	############################################################################################
	datalad create ${opts} -D 'Dataset Template :: Raw Behavioral Data' data/source/behav
	############################################################################################
	# Data Derivatives
	############################################################################################	
	datalad create ${opts} -D 'Dataset Template :: Data Derivations' data/derivatives
	############################################################################################
	# Documents
	############################################################################################	
	datalad create ${opts} -D 'Dataset Template :: Documents' docs
	############################################################################################
	# Bibliography
	############################################################################################	
	datalad create ${opts} -D 'Dataset Template :: Bibliography' docs/biblio	
	############################################################################################
	# External Resources
	############################################################################################	
	datalad create ${opts} -D 'Dataset Template :: External Resources' external
	############################################################################################
	# Add Datalad Super Dataset to External
	############################################################################################
	# datalad install ${opts} -s /// external/datalad
	# TODO what other external items do you need by default?
	############################################################################################
	# done! exit without error if you made it this far
	return 0
}
export -f initialize_dataset_tree
############################################################################################################################################
# --------------------------------------------> 																    Initialize | BIDS format
############################################################################################################################################
# todo add configuration files for bids format
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
function initialize_dataset_bids(){
	indir=${1} && shift # source data directory 
	outdir=${1} && shift # output BIDS directory
	# loop through series and obtain BIDS-required json
	#parallel -o "${dir}"/sub-"${SUBJECT}"/ses-"${SESSION}"/${modality}/
	#dcm2niix  -b o -f ses-"${SESSION}"/${modality}/sub-"${SUBJECT}"_ses-"${SESSION}"_"${SERIES}"-$(printf '%03g' "${SERIES_ORDER}") ${file}
}
############################################################################################################################################
# --------------------------------------------> 															    Initialize | Source MRI Data
############################################################################################################################################
function initialize_dataset_source_mri(){
	local indir=${1} && shift
	local outdir=${1} && shift
	local overwrite=${1} && shift
	############################################################################################
	# Initialize Dataset Meta Data Using Configuration File from OUTDIR
	############################################################################################
	dataset_name=$(cat ${outdir}/dataset_config.tsv |  grep 'Dataset Name' | awk -F '\t| {2,}' '{print $NF}')
	dataset_description=$(cat ${outdir}/dataset_config.tsv |  grep 'Dataset Description' | awk -F '\t| {2,}' '{print $NF}')
	[ ! "${dataset_name}" ] && dataset_name='null'
	[ ! "${dataset_description}" ] && dataset_description='null'
	############################################################################################
	# Initialize Output Directory
	############################################################################################
	dataset_config=${outdir}/dataset_config.json
	if [ ! -d "${outdir}" ]; then
		mkdir -pv "${outdir}"
	fi
	# add configuration file
	# if [ "${overwrite}" ] || [ ! -f "${dataset_config}" ]; then 
	jq -n '{Name: "'"${dataset_name}"'", Description: "'"${dataset_description}"'", Path:"'"${outdir}"'", Subjects: []}' > "${dataset_config}"
	# fi
	echo 'Indexing Input Directory Tree'
	############################################################################################
	# read individual files and create output tree (directories)
	## TODO iterate over folders if possible
	## TODO determine efficient way of delegating recursion over large/deep directory trees
	## NOTE files sorted by name (if time stamp in name then will go in time order)
	## NOTE sessions may not be spit out in order if you batch feed mixed/random files
	############################################################################################
	files=($(tree --du -h -l -f -s -D --device -J "${indir}/" | jq -c '[ .[0] | recurse(.contents[]?) | select( .type | contains("file")) .name]' | sed 's|,| |g' | sed 's|\]||g' | sed 's|\[||g' | sed 's|"||g' | sort -u))
	# create input list for parallel
	printf '%s\n' ${files[@]} > /tmp/init.dataset.source.mri_files.runtime
	(parallel -a /tmp/init.dataset.source.mri_files.runtime -k --link initialize_dataset_source_mri_tree {1} "${outdir}" "${overwrite}" | tee -a /dev/null)
	############################################################################################
	# gather metadata by collapsing individual config files into dataset config
	############################################################################################
	# TODO enumerate sessions by date
	#
	## get list of subjects
	parallel -k --link initialize_dataset_source_mri_metadata_subject {} "${dataset_config}" ::: $(find "${outdir}" -name 'sub-*' -type d -d 1)
	## iterate over subjects and sort/rename sessions
	##
	return 0
}
export -f initialize_dataset_source_mri
############################################################################################################################################
# --------------------------------------------> 											   Initialize | Query DICOM file for Filing Keys
############################################################################################################################################
function initialize_dataset_source_mri_tree_dicom(){
	local file="${1}" && shift
	# default
	LOG="/tmp/init.dataset.source.mri.tree.dicom.runtime.$$"	
	# parse dicom for global variables
	if dcminfo -all "${file}" 1>"${LOG}" 2>/dev/null; then
		SUBJECT="$(cat ${LOG} | grep 'PatientName' | awk -F '\t| {2,}' '{print $NF}' | sed 's| ||g')"
		SUBJECT_SEX="$(cat ${LOG} | grep 'PatientSex' | awk -F '\t| {2,}' '{print $NF}' | sed 's| ||g')"
		SUBJECT_WEIGHT="$(cat ${LOG} | grep 'PatientWeight' | awk -F '\t| {2,}' '{print $NF}' | sed 's| ||g')"
		SUBJECT_DOB="$(cat ${LOG} | grep 'PatientBirthDate' | awk -F '\t| {2,}' '{print $NF}' | sed 's| ||g')"
		SERIES="$(cat ${LOG} | grep 'SeriesDescription' | awk -F '\t| {2,}' '{print $NF}' | sed 's| ||g')"
		SERIES_ORDER="$(cat ${LOG} | grep 'SeriesNumber' | awk -F '\t| {2,}' '{print $NF}' | sed 's| ||g')"
		SERIES_INSTANCE="$(cat ${LOG} | grep 'InstanceNumber' | awk -F '\t| {2,}' '{print $NF}' | sed 's| ||g')"
		SERIES_TIME="$(cat ${LOG} | grep 'AcquisitionTime' | awk -F '\t| {2,}' '{print $NF}' | sed 's| ||g')"
		DATE="$(cat ${LOG} | grep 'StudyDate' | awk -F '\t| {2,}' '{print $NF}' | sed 's| ||g')"
		TIME="$(cat ${LOG} | grep 'StudyTime' | awk -F '\t| {2,}' '{print $NF}' | sed 's| ||g')"
		SEQUENCE="$(cat ${LOG} | grep 'SequenceName' | awk -F '\t| {2,}' '{print $NF}' | sed 's| ||g')"
		FILE_EXT='dicom'
	else
		return 1
	fi	
	[ -f "${LOG}" ] && rm "${LOG}"
	## determine modality of series
	case "${SERIES}" in
		*t1w | *t2w | *dir | *t1w-me | *fgatir | *pd | *flaws | *flair)
			modality='anat'
			;;
		task*_bold)
			modality='func'
			;;
		*dwi)
			modality='dwi'
			;;
		acq-fmap-*)
			modality='fmap'
			;;	
		*)
			modality="other"
			;;
	esac
	#	
	SESSION=$(echo ${DATE}.${TIME} | sed 's|[/|:]|_|g')
	#
	let SUBJECT_AGE=$((`date +%s -d $(echo ${DATE} | sed 's|/||g')` - `date +%s -d $(echo ${SUBJECT_DOB} | sed 's|/||g')`))/31540000
	return 0
}
export -f initialize_dataset_source_mri_tree_dicom
############################################################################################################################################
# --------------------------------------------> 											    		  Initialize | Read Source Data File
############################################################################################################################################
function initialize_dataset_source_mri_tree_read(){
	local file="${1}" && shift
	# check for file existence
	if [ ! -f "${file}" ]; then
		return 0
	fi
	# check if file is dicom
	if initialize_dataset_source_mri_tree_dicom "${file}"; then
		let SUBJECT_AGE=$((`date +%s -d $(echo ${DATE} | sed 's|/||g')` - `date +%s -d $(echo ${SUBJECT_DOB} | sed 's|/||g')`))/31540000
		FILE_EXT='dicom'
		return 0
	fi
	# check if file is nifti
	# read subject name from configuration file
	# file is other
	FILE_EXT='other'
	#
	export FILE_EXT
	# done
	return 0
}
export -f initialize_dataset_source_mri_tree_read
############################################################################################################################################
# --------------------------------------------> 											          Initialize | Write Source Data to Sink
############################################################################################################################################
function initialize_dataset_source_mri_tree_write(){
	local file="${1}" && shift
	local dir="${1}" && shift
	local overwrite="${1}" && shift
	# define tmp file
	local tmpfile=/tmp/tmp.$$.file
	# define dataset configuration
	local dataset_config="${dir}"/dataset_config.json
	# initialize subject directory and configuration
	local subject_config="${dir}"/sub-"${SUBJECT}"/sub-"${SUBJECT}"_config.json
	if [ ! -d "${dir}"/sub-"${SUBJECT}" ]; then
		mkdir "${dir}"/sub-"${SUBJECT}" 2> /dev/null
		jq -n '{"'${SUBJECT}'": {sex:"'${SUBJECT_SEX}'", Sessions:[]}}' > "${subject_config}"
	fi
	## update tree with series x modality
	if [ ! -d "${dir}"/sub-"${SUBJECT}"/ses-"${SESSION}"/${modality} ]; then
		mkdir -p "${dir}"/sub-"${SUBJECT}"/ses-"${SESSION}"/${modality} 2>/dev/null
	fi
	## populate series root with files
	local outfile="${dir}"/sub-"${SUBJECT}"/ses-"${SESSION}"/${modality}/sub-"${SUBJECT}"_ses-"${SESSION}"_"${SERIES}"-$(printf '%03g' "${SERIES_ORDER}")-$(printf '%06g' "${SERIES_INSTANCE}")."${FILE_EXT}"
	if [ "${overwrite}" ] || [ ! -f "${outfile}" ]; then
		cp "${file}" "${outfile}"
	fi	
	# clean up
	[ -f "${tmpfile}" ] && rm "${tmpfile}"
	# done
	return 0 
}
export -f initialize_dataset_source_mri_tree_write
############################################################################################################################################
# --------------------------------------------> 											    Initialize | Copy DICOMs into BIDS Structure
############################################################################################################################################
function initialize_dataset_source_mri_tree(){
	local file="${1}" && shift
	local dir="${1}" && shift
	local overwrite="${1}" && shift
	printf '\033[K\r reading  %s ' "${file}"
	############################################################################################
	# Obtain Meta Data Needed for Tree
	############################################################################################	
	initialize_dataset_source_mri_tree_read "${file}" 
	# exit if json file
	[ "${FILE_EXT}" = 'json' ] && return 0
	# exit if undetermined file (not to be imported)
	[ "${FILE_EXT}" = 'other' ] && return 0
	# exit if subject id is undetermined
	[ ! "${SUBJECT}" ] && return 0
	############################################################################################
	# Build Tree
	############################################################################################
	initialize_dataset_source_mri_tree_write "${file}" "${dir}" "${overwrite}"
	##################################################
	## done
	return 0	
}
export -f initialize_dataset_source_mri_tree
############################################################################################################################################
# --------------------------------------------> 											      Initialize | Sort DICOM files into Session
############################################################################################################################################
function initialize_dataset_source_mri_tree_session(){
	local dir="${1}" && shift
	local dataset_config="${1}" && shift
	# define tmp file
	local tmpfile=/tmp/tmp.$$.file	
	# get subject
	subject=$(echo ${dir} | grep -oE 'sub-.*')
	if [ -z "${subject}" ]; then
		echo 'missing '${dir}
		return 1
	else
		subject_config=${dir}/"${subject}"_config.json
	fi
	# retrieve sessions in subject direstory
	SESSIONS=($(find "${dir}" -name 'ses-*' -type d -d 1 | sort -u))
	counter=0
	########################################################################################################
	# loop across sessions
	########################################################################################################
	for session in ${SESSIONS[*]}; do
		########################################################################################################
		((counter++))
		session_timestamp=$(echo "${session}" | sed 's|/| |g' | awk '{print $NF}')
		session_number="ses-$(printf '%03g' ${counter})"
		session_dir="${dir}"/"${session_number}"	
		# rename session folder
		[ ! -d "${session_dir}" ] && mv "${session}" "${session_dir}"
		########################################################################################################
		# get metadata from each file with sesssion time stamp
		for file in $(find "${session_dir}" -name "*${session_timestamp}*" -type f) ; do
			########################################################################################################
			# DICOM - read metadata from header
			########################################################################################################
			if initialize_dataset_source_mri_tree_dicom "${file}"; then
				printf '\033[K\r converting %s' ${file}
				# write session metadata to file
				session_config="${session_dir}"/"${subject}"_"${session_number}"_config.json
				[ ! -f "${session_config}" ] && jq -n '{"'${session_number}'": [{date:"'${DATE}'", time:"'${TIME}'", age:"'${SUBJECT_AGE}'", kilograms:"'$(printf '%.2f' ${SUBJECT_WEIGHT})'", Acquisitions:[{}]}]}' > "${session_config}"						
				# bids parameters
				bidsjson="sub-"${SUBJECT}"_${session_number}_"${SERIES}"-$(printf '%03g' "${SERIES_ORDER}")"				
				# rename file
				serdir="$(dirname ${file})"
				newfile=$(echo "${file}" | sed 's|/| |g' | awk '{print $NF}' | sed "s|${session_timestamp}|${session_number}|g")
				[ ! -f "${serdir}"/"${newfile}" ] && mv "${file}" "${serdir}"/"${newfile}"
				# write series metadata to file
				series_config=${serdir}/"${subject}"_"${session_number}"_"${SERIES}"-$(printf '%03g' "${SERIES_ORDER}")_config.json	
				if [ ! -f "${series_config}" ]; then 
					jq -n '{Acquisition: {name: "'${SERIES}'",order:'${SERIES_ORDER}', time:"'${SERIES_TIME}'", sequence:"'${SEQUENCE}'", modality:"'${modality}'", "parameters":{}}}' > "${series_config}"
					# fold parameters into acquisition configuration
					if [ ! -f "${bidsjson}.json" ]; then 
						dcm2niix  -b o -o "${serdir}" -f ${bidsjson} ${serdir}
						jq -s '.[0].Acquisition.parameters += .[1] | .[0]' "${series_config}" "${serdir}/${bidsjson}.json" > "${tmpfile}"
						jq '.' "${tmpfile}" > "${series_config}"
					fi					
					# fold series into session
					jq -s '.[0]."'${session_number}'"[].Acquisitions[] += .[1] | .[0]' "${session_config}" "${series_config}" > "${tmpfile}"
					jq '.' "${tmpfile}" > "${session_config}"
				fi
			else
				# skip if not dicom
				continue
			fi
			# INSERT OTHER FILE FORMAT HERE
		done
		########################################################################################################
		# fold session into subject	
		local sessions=$(jq '.'$(echo ${subject} | sed 's|sub-||g')'.Sessions[]."'${session_number}'"' "${subject_config}")
		if [ ! "${sessions}" ]; then
			jq '.'$(echo ${subject} | sed 's|sub-||g')'.Sessions += [{"'${session_number}'":[]}]' "${subject_config}" > "${tmpfile}"
			jq '.' "${tmpfile}" > "${subject_config}"
		fi
		jq -s '.[0]."'$(echo ${subject} | sed 's|sub-||g')'".Sessions[]."'${session_number}'" = .[1]."'${session_number}'" | .[0]' "${subject_config}" "${session_config}" > "${tmpfile}"
		jq '.' "${tmpfile}" > "${subject_config}"			
		########################################################################################################
		# fold subject into dataset configuration
		local subjects=$(jq '.Subjects[]."'$(echo ${subject} | sed 's|sub-||g')'"' ${dataset_config})
		if [ ! "${subjects}" ]; then
			jq '.Subjects += [{"'$(echo ${subject} | sed 's|sub-||g')'":[]}]' "${dataset_config}" > "${tmpfile}"
			jq '.' "${tmpfile}" > "${dataset_config}"
		fi
		jq -s '.[0].Subjects[]."'$(echo ${subject} | sed 's|sub-||g')'" = .[1]."'$(echo ${subject} | sed 's|sub-||g')'" | .[0]' "${dataset_config}" "${subject_config}" > "${tmpfile}"
		jq '.' "${tmpfile}" > "${dataset_config}"
	done
	########################################################################################################
	return 0
}
export -f initialize_dataset_source_mri_tree_session
############################################################################################################################################
# --------------------------------------------> 												   Initialize | Gather MR Metadata | Subject
############################################################################################################################################
function initialize_dataset_source_mri_metadata_subject (){
	local dir=${1} && shift
	local config=${1} && shift
	initialize_dataset_source_mri_tree_session "${dir}" "${config}"
	# done
	return 0
}
export -f initialize_dataset_source_mri_metadata_subject
############################################################################################################################################
# --------------------------------------------> 													     								Main
############################################################################################################################################
# TODO global variables are not available in this call??
function init(){
	parseOpts "${@}"
	initialize_defaults
	if [ ! -d "${DATASET_DIR}" ]; then
		initialize_dataset
	fi
	if [ "${DATASET_SOURCE_DICOM_DIR}" ]; then
		# convert from source tree into bids-ified tree
		initialize_dataset_source_mri "${DATASET_SOURCE_DICOM_DIR}" "${DATASET_DIR}"/data/source/mri "${OVERWRITE}"	
	fi
	## todo check for BIDS CONFIG
	if [ ! -f "${BIDS_CONFIG}" ]; then
		echo ''
		echo 'read subjects from BIDS configration'
		# convert from source tree into bids-ified tree
		#initialize_dataset_bids "${DATASET_SOURCE_DICOM_DIR}" "${DATASET_DIR}"/data/bids "${OVERWRITE}"	
	else
		echo 'read subjects from BIDS configration'
	fi	
	#  todo convert each subject to bids in parallel
	#  todo update bids dir when new source subject is present
	return 0
}
export -f init 
##
init "${@}"
##
############################################################################################################################################
# --------------------------------------------> 													      Initialize | Gather DICOM Metadata
############################################################################################################################################
# DEPRECATED - good example for JQ parsing though
# function deprecated_dicom_parsing(){
# 	local file=${1} && shift
# 	local dir=${1} && shift
# 	# default
# 	LOG="/tmp/main.runtime.$$"	
# 	# parse dicom
# 	if dcminfo -all "${file}" 2>"${LOG}" 1>"${LOG}"; then
# 		isdicom='true'
# 		isnifti='false'
# 		# get information for formatting JSON
# 		subject="$(cat ${LOG} | grep 'PatientName' | awk -F '\t| {2,}' '{print $NF}' | sed 's| ||g')"
# 		dicom_series="$(cat ${LOG} | grep 'SeriesDescription' | awk -F '\t| {2,}' '{print $NF}' | sed 's| ||g')"
# 		dicom_series_order="$(cat ${LOG} | grep 'SeriesNumber' | awk -F '\t| {2,}' '{print $NF}' | sed 's| ||g')"
# 		dicom_series_time="$(cat ${LOG} | grep 'AcquisitionTime' | awk -F '\t| {2,}' '{print $NF}' | sed 's| ||g')"
# 		dicom_date="$(cat ${LOG} | grep 'StudyDate' | awk -F '\t| {2,}' '{print $NF}' | sed 's| ||g')"
# 		dicom_sequence="$(cat ${LOG} | grep 'SequenceName' | awk -F '\t| {2,}' '{print $NF}' | sed 's| ||g')"
# 		############################################################################################
# 		# Append Subject + Date	to Configuration
# 		if [ "$(jq '.Subjects."'${subject}'".Dicom."'${dicom_date}'"' "${dir}"/config.json)" = 'null' ]; then
# 			str="$(printf '"%s": {"Dicom": {"%s": []}}' ${subject} ${dicom_date})"
# 			jq '.Subjects += {'"${str}"'}' "${dir}"/config.json > "${dir}"/tmp.$$.json
# 			jq . "${dir}"/tmp.$$.json > "${dir}"/config.json
# 		fi
# 		############################################################################################
# 		# Append Series to Date		
# 		if [ "$(jq '.Subjects."'${subject}'".Dicom."'${dicom_date}'"['${dicom_series_order}']' "${dir}"/config.json)" = 'null' ]; then
# 			str="$(printf '"%s":{"PulseSequenceName": "%s", 'AcquisitionStartTime': "%s", "Files": []}' ${dicom_series} ${dicom_sequence} ${dicom_series_time})"
# 			jq '.Subjects."'${subject}'".Dicom."'${dicom_date}'"['$(( ${dicom_series_order} - 1 ))'] = {'"${str}"'}' "${dir}"/config.json > "${dir}"/tmp.$$.json
# 			jq . "${dir}"/tmp.$$.json > "${dir}"/config.json			
# 		fi
# 		############################################################################################
# 		# Append BIDS Spec to Series
# 		for field in ${BIDS_DICOM_KEYS}; do
# 			fieldval="\"$(cat ${LOG} | grep "${field}" | awk -F '\t| {2,}' '{print $NF}')\""
# 			[ "${fieldval}" = "\"\"" ] && fieldval='null'
# 			if [ "$(jq '.Subjects."'${subject}'".Dicom."'${dicom_date}'"['$(( ${dicom_series_order} - 1 ))']."'${dicom_series}'"."'${field}'"' "${dir}"/config.json)" = 'null' ]; then
# 				jq '.Subjects."'${subject}'".Dicom."'${dicom_date}'"['$(( ${dicom_series_order} - 1 ))']."'${dicom_series}'" += {"'${field}'": '"${fieldval}"'}' "${dir}"/config.json > "${dir}"/tmp.$$.json
# 				jq . "${dir}"/tmp.$$.json > "${dir}"/config.json			
# 			fi			
# 		done
# 		############################################################################################
# 		# Append Files to Series
# 		if [ "$(jq '.Subjects."'${subject}'".Dicom."'${dicom_date}'"['$(( ${dicom_series_order} - 1 ))']."'${dicom_series}'".Files[-1]' "${dir}"/config.json)" != "${file}" ]; then
# 			jq '.Subjects."'${subject}'".Dicom."'${dicom_date}'"['$(( ${dicom_series_order} - 1 ))']."'${dicom_series}'".Files += ["'${file}'"]' "${dir}"/config.json > "${dir}"/tmp.$$.json
# 			jq . "${dir}"/tmp.$$.json > "${dir}"/config.json
# 		fi
# 	else
# 		return 0
# 	fi
# 	# clean up buffer for json
# 	rm ${dir}/tmp.$$.json
# 	#
# 	return 0
# }
