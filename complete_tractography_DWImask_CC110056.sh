#!/bin/bash

# COMPLETE Tractography pipeline with dwi masking
# Participant: CC110056

set -e  # Exit on any error

# Create working directory
WORK_DIR="/home/fvanderhei/data/CC110056_tractography_dwimask_complete"
PARTICIPANT="sub-CC110056"

# Source paths for CC110056
DWI_SOURCE_DIR="/home/fvanderhei/researchdrive/TSB0020 Neuroimaging_aging (Projectfolder)/Camcan/mri/pipeline/release004/BIDS_20190411/dwi/sub-CC110056/dwi"
ANAT_SOURCE_DIR="/home/fvanderhei/researchdrive/TSB0020 Neuroimaging_aging (Projectfolder)/Camcan/mri/pipeline/release004/BIDS_20190411/anat/sub-CC110056/anat"

echo "Creating working directory: $WORK_DIR"
mkdir -p $WORK_DIR
cd $WORK_DIR

# Create subdirectories
mkdir -p dwi anat

# Copy input data
echo "Copying input data for $PARTICIPANT..."
cp "$DWI_SOURCE_DIR/${PARTICIPANT}_dwi.nii.gz" dwi/
cp "$DWI_SOURCE_DIR/${PARTICIPANT}_dwi.bval" dwi/
cp "$DWI_SOURCE_DIR/${PARTICIPANT}_dwi.bvec" dwi/
cp "$ANAT_SOURCE_DIR/${PARTICIPANT}_T1w.nii.gz" anat/

echo "Starting COMPLETE DWI MASKING tractography pipeline for $PARTICIPANT"
echo "========================================================================="

############################### STEP 1 ###############################
#             Convert data to .mif format and denoise                #
######################################################################

echo "STEP 1: Converting data to .mif format and preprocessing..."

# Convert DWI data to .mif format
mrconvert dwi/${PARTICIPANT}_dwi.nii.gz dwi/dwi.mif 
mrconvert dwi/dwi.mif -fslgrad dwi/${PARTICIPANT}_dwi.bvec dwi/${PARTICIPANT}_dwi.bval dwi/dwi_header.mif 

# Denoise the data
echo "Denoising..."
dwidenoise dwi/dwi_header.mif dwi/dwi_den.mif -noise dwi/noise.mif 

# Remove Gibbs ringing artifacts
echo "Removing Gibbs ringing..."
mrdegibbs dwi/dwi_den.mif dwi/dwi_den_unr.mif 

######################################################################
# Run the dwipreproc command (wrapper for eddy and topup)           #
######################################################################

echo "Running dwifslpreproc (this may take 30-60 minutes)..."
dwifslpreproc dwi/dwi_den_unr.mif dwi/dwi_den_preproc.mif -pe_dir AP -rpe_none -readout_time 0.0342002 -eddy_options " --slm=linear --data_is_shelled" -nthreads 15

# Extract the b0 images from the diffusion data
echo "Extracting b0 images..."
dwiextract dwi/dwi_den_preproc.mif - -bzero | mrmath - mean dwi/mean_b0_AP.mif -axis 3

mrconvert dwi/mean_b0_AP.mif dwi/mean_b0_AP.nii.gz
bet dwi/mean_b0_AP.nii.gz dwi/mean_b0_AP_bet.nii.gz -m -R -f 0.3
mrconvert dwi/mean_b0_AP_bet_mask.nii.gz dwi/mask_for_biascorrection.mif

# Bias field correction
echo "Bias field correction..."
dwibiascorrect fsl dwi/dwi_den_preproc.mif dwi/dwi_den_preproc_unbiased.mif -mask dwi/mask_for_biascorrection.mif -bias dwi/bias.mif 

########################### STEP 2 ###################################
#                          Upsample                                  #
######################################################################

echo "STEP 2: Upsampling..."

# Upsample the diffusion image
mrgrid dwi/dwi_den_preproc_unbiased.mif regrid -vox 1.5 dwi/dwi_unbiased_upsampled.mif

########################### STEP 3 ###################################
#             Response functions with dwi mask                        #
######################################################################

echo "STEP 3: Estimating response functions with dwi-based mask..."

# Estimate response functions using dwi-based mask
dwi2response dhollander dwi/dwi_unbiased_upsampled.mif dwi/wm.txt dwi/gm.txt dwi/csf.txt -voxels dwi/voxels.mif

dwi2mask dwi/dwi_unbiased_upsampled.mif dwi/mask_up.mif

# Perform constrained spherical deconvolution
echo "Performing constrained spherical deconvolution..."
dwi2fod msmt_csd dwi/dwi_unbiased_upsampled.mif -mask dwi/mask_up.mif dwi/wm.txt dwi/wmfod_up.mif dwi/gm.txt dwi/gmfod_up.mif dwi/csf.txt dwi/csffod_up.mif 

# Normalize the FODs
echo "Normalizing FODs..."
mtnormalise dwi/wmfod_up.mif dwi/wmfod_norm_up.mif dwi/gmfod_up.mif dwi/gmfod_norm_up.mif dwi/csffod_up.mif dwi/csffod_norm_up.mif -mask dwi/mask_up.mif 

########################### STEP 4 ###################################
#                        Creating 5TT and coregistration             #
######################################################################

echo "STEP 4: Creating 5TT..."

# Convert anatomical to working formats
mrconvert anat/${PARTICIPANT}_T1w.nii.gz dwi/T1.mif 
mrconvert dwi/T1.mif dwi/T1.nii.gz

# Generate 5-tissue-type segmentation
echo "Generating 5-tissue-type segmentation..."
5ttgen fsl dwi/T1.mif dwi/5tt_nocoreg.mif -nthreads 15
mrconvert dwi/5tt_nocoreg.mif dwi/5tt_nocoreg.nii.gz

# Extract mean b0 for coregistration
dwiextract dwi/dwi_unbiased_upsampled.mif - -bzero | mrmath - mean dwi/mean_b0_processed_up.mif -axis 3
mrconvert dwi/mean_b0_processed_up.mif dwi/mean_b0_processed_up.nii.gz 

# STEP 2B: Coregister T1 to DWI space
echo "Coregistering T1 to DWI space..."
fslroi dwi/5tt_nocoreg.nii.gz dwi/5tt_vol0.nii.gz 0 1
flirt -in dwi/mean_b0_processed_up.nii.gz -ref dwi/5tt_vol0.nii.gz -interp nearestneighbour -dof 6 -omat dwi/diff2struct_fsl_up.mat

# Also create coregistration for other transforms
transformconvert dwi/diff2struct_fsl_up.mat dwi/mean_b0_processed_up.nii.gz dwi/5tt_nocoreg.nii.gz flirt_import dwi/diff2struct_mrtrix_up.txt 
mrtransform dwi/5tt_nocoreg.mif -linear dwi/diff2struct_mrtrix_up.txt -inverse dwi/5tt_coreg_up.mif

#Create a seed region along the GM/WM boundary
echo "Creating GM/WM boundary seed region..."
5tt2gmwmi dwi/5tt_coreg_up.mif dwi/gmwmSeed_coreg_up.mif

########################## STEP 5 ###################################
#                 Run the streamline analysis                        #
######################################################################

echo "STEP 5: Generating streamlines (this may take 1-2 hours)..."

# Generate 10 million tracks
echo "Generating 10 million streamlines..."
tckgen -act dwi/5tt_coreg_up.mif -backtrack -seed_gmwmi dwi/gmwmSeed_coreg_up.mif -nthreads 15 -maxlength 250 -cutoff 0.06 -select 10000k dwi/wmfod_norm_up.mif dwi/tracks_10M_up.tck 

# SIFT2 filtering
echo "Running SIFT2 filtering..."
tcksift2 -act dwi/5tt_coreg_up.mif -out_mu dwi/sift_mu_up.txt -out_coeffs dwi/sift_coeffs_up.txt dwi/tracks_10M_up.tck dwi/wmfod_norm_up.mif dwi/sift_1M_up.txt 

########################## STEP 6 ###################################
#                 Creating the connectome                            #
######################################################################

echo "STEP 6: Creating connectomes..."

# Skull strip T1 (use existing brain extraction)
bet dwi/T1.nii.gz dwi/skullstripped_T1w.nii.gz -R -f 0.3

# Register to MNI space
echo "Registering to MNI space..."
antsRegistrationSyN.sh -d 3 -f /home/fvanderhei/fsl/data/standard/MNI152_T1_1mm_brain.nii.gz -m dwi/skullstripped_T1w.nii.gz -o dwi/T1_to_MNI -n 15

# Transform atlases to subject space
echo "Transforming atlases to subject space..."
antsApplyTransforms -d 3 -i /home/fvanderhei/data/Gordon_Parcels.nii -r dwi/skullstripped_T1w.nii.gz -o dwi/Gordon_Parcels_T1w_space.nii.gz -n NearestNeighbor -t dwi/T1_to_MNI1InverseWarp.nii.gz -t [dwi/T1_to_MNI0GenericAffine.mat,1] -v

antsApplyTransforms -d 3 -i /home/fvanderhei/data/BN_Atlas.nii -r dwi/skullstripped_T1w.nii.gz -o dwi/BN_Atlas_T1w_space.nii.gz -n NearestNeighbor -t dwi/T1_to_MNI1InverseWarp.nii.gz -t [dwi/T1_to_MNI0GenericAffine.mat,1] -v

antsApplyTransforms -d 3 -i /home/fvanderhei/data/MNI_Glasser_HCP_v1.0_afni.nii -r dwi/skullstripped_T1w.nii.gz -o dwi/Glasser_Parcels_T1w_space.nii.gz -n NearestNeighbor -t dwi/T1_to_MNI1InverseWarp.nii.gz -t [dwi/T1_to_MNI0GenericAffine.mat,1] -v

antsApplyTransforms -d 3 -i /home/fvanderhei/data/ROIs_300inVol_MNI.nii -r dwi/skullstripped_T1w.nii.gz -o dwi/Seitzman_Parcels_T1w_space.nii.gz -n NearestNeighbor -t dwi/T1_to_MNI1InverseWarp.nii.gz -t [dwi/T1_to_MNI0GenericAffine.mat,1] -v

# Transform atlases to DWI space
echo "Transforming atlases to DWI space..."
mrtransform dwi/Gordon_Parcels_T1w_space.nii.gz -linear dwi/diff2struct_mrtrix_up.txt -inverse dwi/Gordon_Parcels_DWI_space.nii.gz
mrtransform dwi/BN_Atlas_T1w_space.nii.gz -linear dwi/diff2struct_mrtrix_up.txt -inverse dwi/BN_Atlas_DWI_space.nii.gz
mrtransform dwi/Glasser_Parcels_T1w_space.nii.gz -linear dwi/diff2struct_mrtrix_up.txt -inverse dwi/Glasser_Parcels_DWI_space.nii.gz
mrtransform dwi/Seitzman_Parcels_T1w_space.nii.gz -linear dwi/diff2struct_mrtrix_up.txt -inverse dwi/Seitzman_Parcels_DWI_space.nii.gz

# Upsample atlases to match upsampled DWI
echo "Upsampling atlases to match DWI resolution..."
mrgrid dwi/Gordon_Parcels_DWI_space.nii.gz regrid dwi/dwi_unbiased_upsampled.mif dwi/Gordon_Parcels_DWI_upsampled.nii.gz -interp nearest
mrgrid dwi/BN_Atlas_DWI_space.nii.gz regrid dwi/dwi_unbiased_upsampled.mif dwi/BN_Atlas_DWI_upsampled.nii.gz -interp nearest
mrgrid dwi/Glasser_Parcels_DWI_space.nii.gz regrid dwi/dwi_unbiased_upsampled.mif dwi/Glasser_Parcels_DWI_upsampled.nii.gz -interp nearest
mrgrid dwi/Seitzman_Parcels_DWI_space.nii.gz regrid dwi/dwi_unbiased_upsampled.mif dwi/Seitzman_Parcels_DWI_upsampled.nii.gz -interp nearest

# Create connectomes using upsampled atlases with DWI masking
echo "Creating connectome matrices with T1-based masking..."
tck2connectome -assignment_radial_search 4 -symmetric -zero_diagonal -scale_invnodevol -tck_weights_in dwi/sift_1M_up.txt dwi/tracks_10M_up.tck dwi/Gordon_Parcels_DWI_upsampled.nii.gz dwi/Gordon_parcels_DWImask.txt -out_assignment dwi/assignments_gordon_DWImask.csv

tck2connectome -assignment_radial_search 4 -symmetric -zero_diagonal -scale_invnodevol -tck_weights_in dwi/sift_1M_up.txt dwi/tracks_10M_up.tck dwi/BN_Atlas_DWI_upsampled.nii.gz dwi/BN_Atlas_DWImask.txt -out_assignment dwi/assignments_BN_DWImask.csv

tck2connectome -assignment_radial_search 4 -symmetric -zero_diagonal -scale_invnodevol -tck_weights_in dwi/sift_1M_up.txt dwi/tracks_10M_up.tck dwi/Glasser_Parcels_DWI_upsampled.nii.gz dwi/Glasser_parcels_DWImask.txt -out_assignment dwi/assignments_glasser_DWImask.csv

tck2connectome -assignment_radial_search 4 -symmetric -zero_diagonal -scale_invnodevol -tck_weights_in dwi/sift_1M_up.txt dwi/tracks_10M_up.tck dwi/Seitzman_Parcels_DWI_upsampled.nii.gz dwi/Seitzman_parcels_DWImask.txt -out_assignment dwi/assignments_Seitzman_DWImask.csv

# Clean up
echo "Cleaning up large intermediate files..."
rm dwi/tracks_10M_up.tck

echo "========================================================================="
echo "COMPLETE TRACTOGRAPHY PIPELINE COMPLETED!"
echo "Results are in: $WORK_DIR"
echo ""
echo "CONNECTOME MATRICES:"
echo "  - Gordon: dwi/Gordon_parcels_DWImask.txt"
echo "  - BN Atlas: dwi/BN_Atlas_DWImask.txt"
echo "  - Glasser: dwi/Glasser_parcels_DWImask.txt" 
echo "  - Seitzman: dwi/Seitzman_parcels_DWImask.txt"

