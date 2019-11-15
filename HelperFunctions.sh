####################
# Helper functions #
####################

###################
# Output HH:MM:SS format for a number of seconds.
###################
function printHMS {
	for i in ${*:-$(</dev/stdin)}
	do
		echo $i | awk '{printf "%02d:%02d:%02d\n", $1/3600, ($1%3600)/60, ($1%60)}'
	done
}
export -f printHMS

##
# Outputs minutes from various combinations of time strings:
#  D-H:M:S
#    H:M:S
#      M:S
#      M
##
function printMinutes {
	for i in ${*:-$(</dev/stdin)}
	do
		printSeconds $i | awk '{printf "%.2f\n", $1/60}'
	done
}
export -f printMinutes

##
# Outputs seconds from various combinations of time strings:
#  D-H:M:S
#    H:M:S
#      M:S
#      M
##
function printSeconds {
	for i in ${*:-$(</dev/stdin)}
	do
		echo $i | awk '{
			numHMSBlocks=split($0,hmsBlocks,":")
			
			if (numHMSBlocks == 1) {
				# Minutes only
				printf "%.0f", hmsBlocks[1] * 60
			} else if (numHMSBlocks == 2) {
				# Minutes:Seconds
				printf "%.0f", (hmsBlocks[1] * 60) + hmsBlocks[2]
			} else if (numHMSBlocks == 3) {
				# (days?)-Hours:Minutes:Seconds
				numDHBlocks=split(hmsBlocks[1],dhBlocks,"-")
				if (numDHBlocks == 1) {
					# Hours only.
					printf "%.0f", (dhBlocks[1] * 60 * 60) + (hmsBlocks[2] * 60) + hmsBlocks[3]
				} else {
					# Days-Hours.
					printf "%.0f\n", (dhBlocks[1] * 24 * 60 * 60) + (dhBlocks[2] * 60 * 60) + (hmsBlocks[2] * 60) + hmsBlocks[3]
				}
			}
		}'
	done
}
export -f printSeconds

#######################
# Output basic node information on job failure.
#######################
function scriptFailed {
	echo ""
	echo "$HEADER: SControl -----"
	scontrol show job ${SLURM_JOBID}
	echo ""
	echo "$HEADER: Export -----"
	export
	echo ""
	echo "$HEADER: Storage -----"
	df -ah
	echo ""
}
export -f scriptFailed

#######################
# Output runtime metrics to a log file.
#######################
function failMetrics {
	export SIGTERM="SIGTERM"
	storeMetrics
}
export -f failMetrics

trap "failMetrics" SIGTERM

#######################
# Output runtime metrics to a log file.
#######################
function storeMetrics {
	sleep 10s
	if [ "$SLURM_JOB_NAME" != "" ] && [ "$HEADER" != "" ] && [ "$HEADER" != "CU" ]; then
		case $HEADER in
			RS|PA|SS|CS|BA)
				BACKDIR="../"
				;;
			*)
				BACKDIR=""
		esac
		
		if [ ! -e ${BACKDIR}metrics.txt ]; then
			echo "$logLine" > ${BACKDIR}metrics.txt
		fi
		
		logLine="DateTime,ID,RunTime,Node,CoreAlloc,CoreUtil,MemAlloc,MemUtil,Result,JobName"
		if [ ! -e $HOME/metrics.txt ]; then
			echo "$logLine" > $HOME/metrics.txt
		fi
		
		if [ ! -e $HOME/$(date '+%Y_%m_%d').metrics.txt ]; then
			echo "$logLine" > $HOME/$(date '+%Y_%m_%d').metrics.txt
		fi
		
		jobID=$([ "$SLURM_ARRAY_JOB_ID" != "" ] && echo -ne "${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}" || echo -ne "${SLURM_JOBID}")
		jobString="${jobID}$([ "$JOBSTEP" != "" ] && echo -ne ".${JOBSTEP}")"
		(echo "JobID[.JobStep]:$jobString" 1>&2)
		
		sacct --format jobid%20,jobname%20,elapsed,AveCPU,MinCPU,TotalCPU,UserCPU,CPUTime,CPUTimeRaw -j ${jobID}
		
		jobStats=$(sacct --format JobID%20,JobName%10,UserCPU,CPUTimeRaw,MaxRSS -j $jobString)
		(echo "$jobStats" 1>&2)
		
		JobName=${SLURM_JOB_NAME#*_}
		
		jobLine=$(echo "$jobStats" | grep "\s${jobString}\s")
		(echo "jobline: $jobLine" 1>&2)
		
		UserCPU=$(printSeconds $(echo $jobLine | awk '{print $3}'))	# Convert usercpu time to seconds.
		IdealCPU=$(echo $jobLine | awk '{print $4}')	# CPUTimeRaw is already in seconds.
		CPUUsage=$(echo "$UserCPU $IdealCPU $SLURM_JOB_CPUS_PER_NODE" | awk '{printf "%.2f", (($1 / $2) * $3)}' )
		
		(echo "CPU: ($UserCPU / $IdealCPU) * $SLURM_JOB_CPUS_PER_NODE = $CPUUsage" 1>&2)
		
		MaxRSS=$(echo $jobLine | awk '{print $5}')
		MaxRSSMB=$(echo "${MaxRSS%?}" | awk '{printf "%f", $1 / 1024}')
		MaxMem=$(echo "${SLURM_JOB_CPUS_PER_NODE} ${SLURM_MEM_PER_CPU}" | awk '{printf "%.0f", $1 * $2}' )
		MemUsage=$(echo "$MaxRSSMB $MaxMem" | awk '{printf "%.2f", ($1 / $2)}' )
		(echo "MEM: ($MaxRSSMB / $MaxMem) = $MemUsage" 1>&2)
		
		# Desired log output: DATE.Time, JobID, RunTime, CPUs, CPU Usage, MaxMem, Mem Usage, Completion state, Job Name.
		printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
			"$(date '+%Y-%m-%d %H:%M:%S')" \
			$jobString \
			$(printHMS $SECONDS) \
			${SLURM_NODELIST//compute-/} \
			$SLURM_JOB_CPUS_PER_NODE \
			$([ "$CPUUsage" != "" ] && echo -ne "$CPUUsage" || echo -ne "0.0") \
			$([ "$MaxMem" != "" ] && echo -ne "$MaxMem" || echo -ne "0.0") \
			$([ "$MaxRSSMB" != "" ] && echo -ne "$MaxRSSMB" || echo -ne "0.0") \
			$([ "$SIGTERM" != "" ] && echo -ne "$SIGTERM" || echo -ne "PASS") \
			${SB[$HEADER]} \
			"${JobName}$([ "$SLURM_ARRAY_JOB_ID" != "" ] && echo -ne ":$SLURM_ARRAY_TASK_ID")" | \
			tee -a ${BACKDIR}metrics.txt | \
			tee -a $HOME/metrics.txt >> \
			$HOME/$(date '+%Y_%m_%d').metrics.txt
	fi
}
export -f storeMetrics

#trap "storeMetrics" EXIT

#####################
# Return a string with a new item on the end
# Items are separated by a char or space
#####################
function appendList {
	oldList="${1}"
	newItem="${2}"
	itemJoiner=$([ "${3}" == "" ] && echo -ne " " || echo -ne "${3}")	# If blank, use space.
	
#	(>&2 echo "${oldList}${itemJoiner}${newItem}")
	
	if [ "$newItem" != "" ]; then
		if [ "$oldList" == "" ]; then
			# Initial Entry
			printf "%s" "$newItem"
		else
			# Additional Entry
			printf "%s%s%s" "$oldList" "$itemJoiner" "$newItem"
		fi
	else
		printf "%s" "$oldList"
	fi
}
export -f appendList

######################
# Return the string with the split char replaced by a space
######################
function splitByChar {
	input=${1}
	char=${2}
	
	if [ "$char" != "" ]; then
		echo -ne "$input" | sed -e "s/${char}/ /g"
	else
		echo -ne "FAIL"
		(>&2 echo -ne "FAILURE:\t splitByChar [${1}] [${2}]\n\tNo character to replace. You forget to quote your input?\n")
	fi
}
export -f splitByChar

######################
# Find matching task elements in a parent and child array.
# Set the child array task element to be dependent on the matching parent task element.
######################
function tieTaskDeps {
	childArray=$(expandList ${1})
	childJobID=${2}
	parentArray=$(expandList ${3})
	parentJobID=${4}
	
	if [ "$childArray" != "" ] && [ "$parentArray" != "" ]; then
		# Both arrays contain something.
		# Cycle through child array elements
		for i in $(splitByChar "$childArray" ","); do
			elementMatched=0
			# Cycle through parent array elements.
			for j in $(splitByChar "$parentArray" ","); do
				if [ "$i" == "$j" ]; then
					# Matching element found. Tie child element to parent element.
#					printf " T[%s->%s] " "${childJobID}_$i" "${parentJobID}_$j"
					scontrol update JobId=${childJobID}_$i Dependency=afterok:${parentJobID}_$j
					elementMatched=1
				fi
			done
			if [ $elementMatched -eq 0 ]; then
				# No matching element found in parent array.
				# Release child element from entire parent array.
				scontrol update JobId=${childJobID}_$i Dependency=
			fi
			tickOver
		done
	fi
}
export -f tieTaskDeps

##################
# Create output olders in the temp and final destination locations.
##################
function outDirs {
	# Make sure destination location exists.
	if ! mkdir -p $(dirname ${OUTPUT}); then
		echo "$HEADER: Unable to create output folder ${PWD}/${OUTPUT}!"
		exit 1
	fi
	
	if ! mkdir -p $(dirname ${JOB_TEMP_DIR}/${OUTPUT}); then
		echo "$HEADER: Unable to create temp output folder ${JOB_TEMP_DIR}/${OUTPUT}!"
		exit 1
	fi
}
export -f outDirs

##################
# Check if final output exists.
##################
function outFile {
	if [ -e ${OUTPUT}.done ]; then
		# Done file exists. why are we here?
		echo "$HEADER: Output file \"${OUTPUT}\" already completed!"
		exit 0
	elif [ -e ${OUTPUT} ]; then
		# Output already exists for this process. Overwrite!
		echo "$HEADER: Output file \"${OUTPUT}\" already exists. Overwriting!"
	fi
}
export -f outFile

#################
# Make sure input file exists
#################
function inFile {
	if [ ! -e "${INPUT}" ]; then
		echo "$HEADER: Input file \"${INPUT}\" doesn't exists!"
		ls -la $(dirname $INPUT)
		exit 1
	fi
}
export inFile

###################
# Move temp output to final output locations
###################
function finalOut {
	if ! mv ${JOB_TEMP_DIR}/${OUTPUT%.*}* $(dirname ${OUTPUT}); then
		echo "$HEADER: Failed to move ${JOB_TEMP_DIR}/${OUTPUT} to ${PWD}/${OUTPUT}!"
		exit 1
	fi
}
export -f finalOut

###################
# Move temp output to final output locations
###################
function scratchOut {
	if ! mv ${SCRATCH_DIR}/${OUTPUT%.*}* $(dirname ${OUTPUT}); then
		echo "$HEADER: Failed to move ${SCRATCH_DIR}/${OUTPUT} to ${PWD}/${OUTPUT}!"
		exit 1
	fi
}
export -f scratchOut

####################
# Check if command filed
####################
function cmdFailed {
	exitCode=$1
	echo "$HEADER: [$SLURM_JOB_NAME:$SLURM_JOBID:$SLURM_ARRAY_TASK_ID] failed with $exitCode!"
	SIGTERM="FAIL($exitCode)"
}
export -f cmdFailed

###################
# Outputs a dependency if one exists.
###################
function depCheck {
	#(echo "depCheck: $0 \"${@}\"" | tee -a ~/depCheck.txt 1>&2)
	local jobList=$(jobsExist "$1")
	[ "$jobList" != "" ] && echo -ne "--dependency afterok:${jobList}"
}
export -f depCheck

function depCheckArray {
	#(echo "depCheckArray $0 \"${@}\"" | tee -a ~/depCheck.txt 1>&2)
	local jobList=$(jobsExist "$1")
	[ "$jobList" != "" ] && echo -ne "--dependency aftercorr:${jobList}"
}
export -f depCheckArray

function depCheckAny {
	#(echo "depCheckArray $0 \"${@}\"" | tee -a ~/depCheck.txt 1>&2)
	local jobList=$(jobsExist "$1")
	[ "$jobList" != "" ] && echo -ne "--dependency afterany:${jobList}"
}
export -f depCheckAny

####################
# Returns true if the list of jobs passed are running or waiting to run, otherwise false
####################
function jobsExist {
	local jobList=""
	local IFS=':'
	for item in $@
	do
		if squeue -j $item | grep "$item" &>/dev/null
		then
			jobList=$(appendList "$jobList" $item ":")
		fi
	done
	echo "$jobList"
}
export -f jobsExist

###################
# Gets job category data
###################
function dispatch {
	#jobWait
	JOBCAT=${1}
	if [ "$MAIL_USER" != "" ]; then
		mailOut="--mail-user $MAIL_USER --mail-type $MAIL_TYPE "
	else
		mailOut=" "
	fi
	
	if [ "$PLATFORM" != "Genomic" ] && [ "${SB[$JOBCAT,MWT,EXOME]}" != "" ]; then
		wallTime="${SB[$JOBCAT,MWT,EXOME]}"
	else
		wallTime="${SB[$JOBCAT,MWT]}"
	fi
	
	echo -ne "${mailOut} --time $wallTime --mem ${SB[$JOBCAT,MEM]} --cpus-per-task ${SB[$JOBCAT,CPT]}"
}
export -f dispatch

###################
# Echo job stats to log file
###################
function jobStats {
echo -e "$HEADER:\tWalltime: $(printHMS $(printSeconds ${SB[$HEADER,MWT]}))"
	echo -e "\tCores:    ${SB[$HEADER,CPT]}"
	echo -e "\tMemory:   ${SB[$HEADER,MEM]}"
}
export -f jobStats

##################
# Delays job submission based on project's previous submitted job.
#
# Limits submission rate to 1 job every MAX_JOB_RATE seconds.
##################
function jobWait {
	timeNow=$(date +%s)
	if [ -e ${PROJECT}/submitted.log ]; then
		lastJob=$(cat ${PROJECT}/submitted.log)
		if [ "$lastJob" != "" ]; then
			while [ $(($timeNow - $lastJob)) -lt $MAX_JOB_RATE ]; do
				tickOver
				
				sleep 0.25s
				timeNow=$(date +%s)
			done
		fi
	fi
	echo $timeNow > ${PROJECT}/submitted.log
}
export -f jobWait

###################
# Visual ticker
###################
function tickOver {
	case "$TICKER" in
		"|") TICKER="/" ;;
		"/") TICKER="-" ;;
		"-") TICKER="\\" ;;
		*) TICKER="|" ;;
	esac
	
	>&2 printf "%s\b" "$TICKER"
}
export -f tickOver

#######################
# Condenses list of numbers to ranges
#
# 1,2,3,4,7,8,9,12,13,14 -> 1-3,4,7-9,12-14
#######################
function condenseList {
	echo "${@}," | \
		sed "s/,/\n/g" | \
		while read num
		do
		if [[ -z $first ]]
		then
			first=$num
			last=$num
			continue
		fi
		if [[ num -ne $((last + 1)) ]]
		then
			if [[ first -eq last ]]
			then
				echo $first
			else
				echo $first-$last
			fi
			first=$num
			last=$num
		else
			: $((last++))
		fi
	done | paste -sd ","
}
export -f condenseList

#####################
# Expand comma separated list of ranges to individual elements
#
# 1,3-5,8,10-12 -> 1,3,4,5,8,10,11,12
#####################
function expandList {
	for f in ${1//,/ }; do
		if [[ $f =~ - ]]; then
			a+=( $(seq ${f%-*} 1 ${f#*-}) )
		else
			a+=( $f )
		fi  
	done
	
	a=${a[*]}
	a=${a// /,}
	
	echo $a
}
export -f expandList

###################
# Returns full path to specified file.
###################
function realpath {
	echo $(cd $(dirname $1); pwd)/$(basename $1);
}
export -f realpath

# check if stdout is a terminal...
if test -t 1; then

    # see if it supports colors...
    ncolors=$(tput colors)

    if test -n "$ncolors" && test $ncolors -ge 8; then
        bld="$(tput bold)"
        und="$(tput smul)"
        std="$(tput smso)"
        nrm="$(tput sgr0)"
        blk="$(tput setaf 0)"
        red="$(tput setaf 1)"
        grn="$(tput setaf 2)"
        ylw="$(tput setaf 3)"
        blu="$(tput setaf 4)"
        mag="$(tput setaf 5)"
        cyn="$(tput setaf 6)"
        wht="$(tput setaf 7)"
        gry="$(tput setaf 8)"
        bred="$(tput setaf 9)"
        bgrn="$(tput setaf 10)"
        bylw="$(tput setaf 11)"
        bblu="$(tput setaf 12)"
        bmag="$(tput setaf 13)"
        bcyn="$(tput setaf 14)"
        bwht="$(tput setaf 15)"
    fi
fi


