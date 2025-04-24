# Initiate algoritm to deconvolce the fiber orientation distributions (FODs)
dwi2response dhollander Subject2_den_preproc_unbiased.mif wm.txt gm.txt csf.txt -voxels voxels.mif

# Estimate white matter, gray matter, and CSF fiber orientation distributions using multi-tissue CSD from preprocessed DWI data.
dwi2fod msmt_csd Subject2_den_preproc_unbiased.mif -mask mask.mif wm.txt wmfod.mif gm.txt gmfod.mif csf.txt csffod.mif

# Extract the first volume of the WM FOD image and concatenate it with CSF and GM FODs to create a 3-tissue volume fraction image.
mrconvert -coord 3 0 wmfod.mif - | mrcat csffod.mif gmfod.mif - vf.mif

# Perform multi-tissue FOD intensity normalization across WM, GM, and CSF using a brain mask.
mtnormalise wmfod.mif wmfod_norm.mif gmfod.mif gmfod_norm.mif csffod.mif csffod_norm.mif -mask mask.mif


# The anatomical image first needs to be converted to MRtrix format
mrconvert sub-CC110045_T1w.nii t1.mif

# Segment the anatomical image into the 5 tissue types
5ttgen fsl T1.mif 5tt_nocoreg.mif

# Extract b=0 volumes from the DWI data and compute the mean across them, saving the result as `mean_b0.mif`.
dwiextract Subject2_den_preproc_unbiased.mif - -bzero | mrmath - mean mean_b0.mif -axis 3

# Move the `5tt_nocoreg.mif` file to the current directory and convert `mean_b0.mif` and `5tt_nocoreg.mif` to NIfTI format (`.nii.gz`).
mv ../anat/5tt_nocoreg.mif .
mrconvert mean_b0.mif mean_b0.nii.gz
mrconvert 5tt_nocoreg.mif 5tt_nocoreg.nii.gz

##Need fsl

# Extract the first volume (index 0) from the `5tt_nocoreg.nii.gz` file and save it as `5tt_vol0.nii.gz`.
fslroi 5tt_nocoreg.nii.gz 5tt_vol0.nii.gz 0 1

#We then use the flirt command to coregister the two datasets:
flirt -in mean_b0.nii.gz -ref 5tt_vol0.nii.gz -interp nearestneighbour -dof 6 -omat diff2struct_fsl.mat

# Convert the transformation matrix from FSL format into MRtrix-readable format using `transformconvert`.
transformconvert diff2struct_fsl.mat mean_b0.nii.gz 5tt_nocoreg.nii.gz flirt_import diff2struct_mrtrix.txt

# Applies the inverse of a linear transformation (diff2struct_mrtrix.txt) to the 5-tissue-type image (5tt_nocoreg.mif) to align it with diffusion space
mrtransform 5tt_nocoreg.mif -linear diff2struct_mrtrix.txt -inverse 5tt_coreg.mif

# This command extracts the gray matter–white matter interface (GMWMI) from the coregistered 5-tissue-type image (`5tt_coreg.mif`) and saves it as a seed mask (`gmwmSeed_coreg.mif`) for anatomically constrained tractography.
5tt2gmwmi 5tt_coreg.mif gmwmSeed_coreg.mif

# This command generates 10 million streamlines using anatomically constrained tractography (`-act`), backtracking for better termination (`-backtrack`), seeding from the gray matter–white matter interface (`-seed_gmwmi`), and several other parameters (e.g., max length, FOD cutoff, threading), saving the output to `tracks_10M.tck`.
tckgen -act 5tt_coreg.mif -backtrack -seed_gmwmi gmwmSeed_coreg.mif -nthreads 8 -maxlength 250 -cutoff 0.06 -select 10000000 wmfod_norm.mif tracks_10M.tck

# To counter-balance this overfitting, the command tcksift2 will create a text file containing weights for each voxel in the brain:
tcksift2 -act 5tt_coreg.mif -out_mu sift_mu.txt -out_coeffs sift_coeffs.txt -nthreads 8 tracks_10M.tck wmfod_norm.mif sift_1M.txt

# Sets the `SUBJECTS_DIR` environment variable to the current working directory (returned by the `pwd` command), telling FreeSurfer where to look for or save subject data.
SUBJECTS_DIR='pwd'

# runs FreeSurfer’s full cortical reconstruction and segmentation pipeline (-all) on the input T1-weighted image, assigning the results to a subject directory named Sub-CON02_recon.
recon-all -i sub-CC110045_T1w.nii -s sub-CON02_recon -all