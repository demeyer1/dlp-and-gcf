#!/bin/bash
# Copyright 2016 Google Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# 

# create variables for the gcs buckets that will be used
# quarantine is where the files are copied to start the process
# a CF will be triggered which will process the file using DLP API
# CF will then move the file from quarantine to either sensitive or non-sensitive depending on the return value of DLP
declare -r BUCKET_NonSensitive="gs://non_sensitive_data"
declare -r BUCKET_Sensitive="gs://sensitive_data"
declare -r BUCKET_Quarantine="gs://quarantine_bucket"

# user is prompted to use the small dataset (40 files) or the large dataset (600 files)
echo "Do you want to use (S)mall or (L)arge sample set? [ENTER]:"
read sample_size

#start by cleaning up existing classification buckets - Cleanup DLP-processed directories
echo "Clean up"
gsutil -m rm ${BUCKET_NonSensitive}/*
gsutil -m rm ${BUCKET_Sensitive}/*
gsutil -m rm ${BUCKET_Quarantine}/*

#copy the files from the sample storage bucket into the quarantine to start processing
#TODO: improvement: could handle both capital S and small S and also handle L and l versus any other entry
if [ "$sample_size" == "S" ]; then
  gsutil -m cp gs://sample_data_small/* ${BUCKET_Quarantine}  
  echo "Using small sample size"
else
  gsutil -m cp gs://sample_data_large/* ${BUCKET_Quarantine}
  echo "Using large sample size"
fi

#use gsutil to get a count of the files in the gcs bucket and pipe to a file
gsutil du ${BUCKET_Sensitive} | wc -l  > gsutil_du.txt 
path="gsutil_du.txt"
#get the latest count
sensitive_result=$(tail "$path")

gsutil du ${BUCKET_NonSensitive} | wc -l  > gsutil_du.txt 
path="gsutil_du.txt"
non_sensitive_result=$(tail "$path")

gsutil du ${BUCKET_Quarantine} | wc -l  > gsutil_du.txt 
path="gsutil_du.txt"
result=$(tail "$path")
#output the total number of files to be processed as counted from quarantine bucket
echo "Files to be processed: " $result 


#while there are files left in the quarantine bucket, keep counting
#TODO: enhancement - if CF has an error, the file will remain in the quarantine bucket so this will become an infinite loop as those files never get processed
last_count=$result

x=$result 
repeat_count=0

while [ $x -gt 0 ]; 
do 
  gsutil du ${BUCKET_Sensitive} | wc -l > gsutil_du.txt 
  path="gsutil_du.txt"
  sensitive_result=$(tail "$path")
  
  gsutil du ${BUCKET_NonSensitive} | wc -l > gsutil_du.txt 
  path="gsutil_du.txt"
  non_sensitive_result=$(tail "$path")
  #print number of files that have been processed and put into the sensitive and non-sensitive storage buckets
  echo "Sensitive/Non-sensitive: " $sensitive_result "/" $non_sensitive_result
  
  # get number of non-processed files
  gsutil du ${BUCKET_Quarantine} | wc -l  > gsutil_du.txt 
  path="gsutil_du.txt"
  x=$(tail "$path")
  result=$x
  echo "Files to be processed: " $result
  
  #echo "Lastcount/result: " $last_count $result
  
  #if the number processed has not changed, it is likely stuck, but allow 5 loops before exiting
  if [ "$last_count" -ne "$result" ]
  then
    last_count=$result
    repeat_count=0
  else
   	if [ $repeat_count -gt 4 ];then
  	  #exit out by setting x to 0
  	  echo "Jump out of loop!"
  	  x=0
  	else
      repeat_count=$[$repeat_count+1]
    fi
  fi
  
done

#get the final count of files categorized and output
gsutil du ${BUCKET_Sensitive} | wc -l > gsutil_du.txt 
path="gsutil_du.txt"
sensitive_result=$(tail "$path")
  
gsutil du ${BUCKET_NonSensitive} | wc -l > gsutil_du.txt 
path="gsutil_du.txt"
non_sensitive_result=$(tail "$path")
  
echo "Final # of Non-sensitive files: " $non_sensitive_result
echo "Final # of Sensitive files: " $sensitive_result
echo "Files not processed: " $result
#remove gsutil_du.txt file
rm gsutil_du.txt
