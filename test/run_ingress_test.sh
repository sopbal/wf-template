#!/bin/bash
set -exo pipefail

get-test_data-from-aws () {
    # get aws-cli
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip

    # get test data
    aws/dist/aws s3 cp --recursive --quiet --no-sign-request \
        "$S3_TEST_DATA" \
        test_data_from_S3
}

sample_sheet=""
chunks=""

while getopts 's:c:' option; do
  case "$option" in
    s ) sample_sheet=$OPTARG;;
    c ) chunks="--chunk $OPTARG";;
  esac
done
input_path=${@:$OPTIND:1}
input_type=${@:$OPTIND+1:1}
wf_output_dir=${@:$OPTIND+2:1}

valid=true
if [ -z $input_path ]; then valid=false; fi
if [ -z $input_type ]; then valid=false; fi
if [ -z $wf_output_dir ]; then valid=false; fi
if ! $valid; then
    echo "run_ingress_test.sh [-s sample_sheet] [-c chunksize] input input_type output"
    exit 1
fi

# get test data from s3 if required
if [[ $input_path =~ ^s3:// ]]; then
    get-test_data-from-aws
    input_path="$PWD/test_data_from_S3/${input_path#*test_data/}"
    [[ -n $sample_sheet ]] &&
        sample_sheet="$PWD/test_data_from_S3/${sample_sheet#*test_data/}"
fi

# add CWD if paths are relative
[[ ( $input_path != /* ) ]] && input_path="$PWD/$input_path"
[[ ( $wf_output_dir != /* ) ]] && wf_output_dir="$PWD/$wf_output_dir"
[[ ( -n $sample_sheet ) && ( $sample_sheet != /* ) ]] &&
    sample_sheet="$PWD/$sample_sheet"

# add flags to parameters (`$input_path` could contain a space; so need to use an array
# here)
input_path=("--input" "$input_path")
input_type="--type $input_type"
wf_output_dir="--wf-output-dir $wf_output_dir"
[[ -n $sample_sheet ]] && sample_sheet="--sample_sheet $sample_sheet"

# get container hash from config
img_hash=$(grep 'common_sha.\?=' nextflow.config | grep -oE '(mr[0-9]+_)?sha[0-9,a-f,A-F]+')

# run test
docker run -u $(id -u) -v "$PWD":"$PWD" \
    ontresearch/wf-common:"$img_hash" \
    python "$PWD/test/test_ingress.py" "${input_path[@]}" $input_type $wf_output_dir $sample_sheet $chunks
