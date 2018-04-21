#!/bin/bash

script_name=`basename $0`
script_dir=`dirname $0`
version="???"

if [ -f "$script_dir/VERSION" ] ; then
   version=`cat $script_dir/VERSION`
fi

gpu="0"

function usage()
{
    echo "usage: $script_name [-h]
                      predictdir

              Version: $version

              Runs caffe prediction on CDeep3M trained model using
              predict.config file to obtain location of trained
              model and image data

positional arguments:
  predictdir           Predict directory generated by
                       runprediction.sh

optional arguments:
  -h, --help           show this help message and exit

    " 1>&2;
   exit 1;
}

TEMP=`getopt -o h --long "help" -n '$0' -- "$@"`
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -h ) usage ;;
        --help ) usage ;;
        --) shift ; break ;;
    esac
done

if [ $# -ne 1 ] ; then
  usage
fi

out_dir=$1

echo ""

predict_config="$out_dir/predict.config"

if [ ! -s "$predict_config" ] ; then
  echo "ERROR no $predict_config file found"
  exit 2
fi

trained_model_dir=`egrep "^ *trainedmodeldir *=" "$predict_config" | sed "s/^.*=//" | sed "s/^ *//"`

img_dir=`egrep "^ *imagedir *=" "$predict_config" | sed "s/^.*=//" | sed "s/^ *//"`
model_list=`egrep "^ *models *=" "$predict_config" | sed "s/^.*=//" | sed "s/^ *//"`
aug_speed=`egrep "^ *augspeed *=" "$predict_config" | sed "s/^.*=//" | sed "s/^ *//"`

echo "Running Prediction"
echo ""

echo "Trained Model Dir: $trained_model_dir"
echo "Image Dir: $img_dir"
echo "Models: $model_list"
echo "Speed: $aug_speed"
echo ""

package_proc_info="$img_dir/package_processing_info.txt"

if [ ! -s "$package_proc_info" ] ; then
  echo "ERROR $package_proc_info not found"
  exit 3
fi

num_pkgs=`head -n 3 $package_proc_info | tail -n 1`
num_zstacks=`tail -n 1 $package_proc_info`

for Y in `echo "$model_list" | sed "s/,/ /g"` ; do
  for CUR_PKG in `seq 001 $num_pkgs` ; do
    for CUR_Z in `seq 01 $num_zstacks` ; do
      model_name=`basename $Y`
      echo "Running $model_name predict $num_pkgs package(s) to process"
      let cntr=1
      pkg_name="Pkg${CUR_PKG}_Z${CUR_Z}"
      Z="$img_dir/$model_name/$pkg_name"
      out_pkg="$out_dir/$model_name/$pkg_name"
      if [ -f "$out_pkg/DONE" ] ; then
        echo "Found $out_pkg/DONE. Prediction completed. Skipping..."
        continue
      fi
      echo -n "  Processing $pkg_name $cntr of $num_pkgs "
      outfile="$out_pkg/out.log"
      PreprocessPackage.m "$img_dir" "$out_pkg" $CUR_PKG $CUR_Z $Y $aug_speed
      ecode=$?
      if [ $? != 0 ] ; then
        echo "ERROR, a non-zero exit code ($ecode) was received from: PreprocessPackage.m \"$img_dir\" \"$out_pkg\" $CUR_PKG $CUR_Z $Y $aug_speed"
        exit 4
      fi

      /usr/bin/time -p caffepredict.sh --gpu $gpu "$trained_model_dir/$model_name/trainedmodel" "$Z" "$out_pkg"
      ecode=$?
      if [ $ecode != 0 ] ; then
        echo "ERROR, a non-zero exit code ($ecode) was received from: /usr/bin/time -p caffepredict.sh --gpu $gpu \"$trained_model_dir/$model_name/trainedmodel\" \"$Z\" \"$out_pkg\""
        if [ -f "$outfile" ] ; then
          echo "Here is last 10 lines of $outfile:"
          echo ""
          tail $outfile
        fi
        exit 5
      fi
      echo "Prediction completed: `date +%s`" > "$Z/DONE"
      let cntr+=1
    done
  if [ -f "$Y/DONE" ] ; then
    echo "Found $Y/DONE. Merge completed. Skipping..."
    continue
  fi
  echo ""
  echo "Running Merge_LargeData.m $Y"
  merge_log="$Y/merge.log"
  Merge_LargeData.m "$Y" >> "$merge_log" 2>&1
  ecode=$?
  if [ $ecode != 0 ] ; then
    echo "ERROR non-zero exit code ($ecode) from running Merge_LargeData.m"
    exit 6
  fi
  echo "Merge completed: `date +%s`" > "$Y/DONE"
done

echo ""
echo "Prediction has completed. Have a nice day!"
echo ""
