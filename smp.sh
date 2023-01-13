# slurm my priority

OUTPUT=$(sbatch /home1/hoonrae/cluster-remains/dummy_job.sh)
JOB_ID=$(cut -d" " -f4 <<< $OUTPUT)
JOB_INFO=$(scontrol show job $JOB_ID)

for INFO in $JOB_INFO
do
    if [[ $INFO == Priority* ]]
    then
        PRIORITY=$(cut -d"=" -f2 <<< $INFO)
    fi
done
echo My Priority: $PRIORITY
$(scancel "$JOB_ID")
