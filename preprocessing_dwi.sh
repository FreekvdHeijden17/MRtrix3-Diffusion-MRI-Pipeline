#!/bin/bash

## If you use docker (otherwise skip to line 10):

## Run MRtrix3 Docker container
docker run -it --rm -v "C:\Users\u361338\OneDrive - Tilburg University\Documenten\MRITRIX":/data mrtrix3/mrtrix3

# Inside Docker (in command line):

# Go to subject folder
cd /data/Subject2

# Convert DWI NIfTI to MRtrix format (.mif)
mrconvert sub-CC110045_dwi.nii.gz sub-CC110045_dwi.mif -fslgrad sub-CC110045_dwi.bvec sub-CC110045_dwi.bval

# Rename files for clarity
mv sub-CC110045_dwi.bvec Subject2.bvec
mv sub-CC110045_dwi.bval Subject2.bval
mv sub-CC110045_dwi.nii.gz Subject2_dwi.nii.gz
mv sub-CC110045_dwi.json Subject2_dwi.json

# Check image information
mrinfo Subject2_dwi.mif

# Verify number of volumes
mrinfo -size Subject2_dwi.mif | awk '{print $4}'
awk '{print NF; exit}' Subject2.bvec
awk '{print NF; exit}' Subject2.bval

# Denoising
dwidenoise Subject2_dwi.mif Subject2_den.mif -noise noise.mif

# Remove Gibbs ringing 
mrdegibbs Subject2_den.mif Subject2_den_unr.mif

# Motion and Eddy current correction (without reverse phase encoding images)
dwifslpreproc Subject2_den.mif Subject2_den_preproc.mif -nocleanup -pe_dir AP -rpe_none -eddy_options "--slm=linear --data_is_shelled"

# Generating a Mask
dwibiascorrect ants Subject2_den_preproc.mif Subject2_den_preproc_unbiased.mif -bias bias.mif

# Restrict your analysis to voxels that are located within the brain:
dwi2mask Subject2_den_preproc_unbiased.mif mask.mif