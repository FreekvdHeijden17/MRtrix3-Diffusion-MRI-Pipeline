# MRtrix3 Diffusion MRI Pipeline - Complete Tractography with DWI Masking

This repository contains a complete bash script for processing diffusion MRI data using MRtrix3, including preprocessing, fiber orientation distribution analysis, tractography, and connectome generation with multiple brain atlases.

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Pipeline Steps](#pipeline-steps)
  1. [Data Conversion and Preprocessing](#1-data-conversion-and-preprocessing)
  2. [Upsampling](#2-upsampling)
  3. [Response Function Estimation with DWI Masking](#3-response-function-estimation-with-dwi-masking)
  4. [5TT Generation and Coregistration](#4-5tt-generation-and-coregistration)
  5. [Streamline Generation](#5-streamline-generation)
  6. [Connectome Creation](#6-connectome-creation)
- [Output Files](#output-files)
- [References](#references)

## Overview

This pipeline provides a complete end-to-end solution for diffusion MRI processing, specifically designed for the CamCAN dataset. The script processes a single participant (CC110056) through the entire tractography workflow, including:

### Key Features
- **Complete automation**: Single script execution for entire pipeline
- **DWI-based masking**: Uses diffusion-derived masks for improved analysis
- **Multiple atlases**: Generates connectomes for Gordon, BN Atlas, Glasser, and Seitzman parcellations
- **Quality preprocessing**: Includes denoising, Gibbs ringing removal, and bias correction
- **Anatomically-constrained tractography**: Uses 5-tissue-type segmentation for biologically plausible streamlines
- **SIFT2 optimization**: Applies streamline filtering for more accurate connectivity weights

### Processing Highlights
- Upsampling to 1.5mm isotropic resolution
- Multi-shell multi-tissue constrained spherical deconvolution (MSMT-CSD)
- 10 million streamline generation with anatomical constraints
- Coregistration between diffusion and structural spaces
- Atlas transformation from MNI to native DWI space

## Prerequisites

- **MRtrix3** (with all dependencies)
- **FSL** (including FLIRT, BET, and dwifslpreproc)
- **ANTs** (for registration and transformation)
- **15+ CPU cores** (script uses 15 threads)
- **Sufficient disk space** (~50GB per subject for intermediate files)

### Required Input Data Structure
```
DWI_SOURCE_DIR/
├── sub-CC110056_dwi.nii.gz
├── sub-CC110056_dwi.bval
└── sub-CC110056_dwi.bvec

ANAT_SOURCE_DIR/
└── sub-CC110056_T1w.nii.gz
```

### Required Atlas Files
The script expects these atlas files in `/home/fvanderhei/data/`:
- `Gordon_Parcels.nii`
- `BN_Atlas.nii`
- `MNI_Glasser_HCP_v1.0_afni.nii`
- `ROIs_300inVol_MNI.nii` (Seitzman parcellation)

## Pipeline Steps

### 1. Data Conversion and Preprocessing

**Duration: ~30-60 minutes**

```bash
# Convert to MRtrix format
mrconvert dwi/sub-CC110056_dwi.nii.gz dwi/dwi.mif 
mrconvert dwi/dwi.mif -fslgrad dwi/sub-CC110056_dwi.bvec dwi/sub-CC110056_dwi.bval dwi/dwi_header.mif 

# Denoise the data
dwidenoise dwi/dwi_header.mif dwi/dwi_den.mif -noise dwi/noise.mif 

# Remove Gibbs ringing artifacts
mrdegibbs dwi/dwi_den.mif dwi/dwi_den_unr.mif 

# FSL preprocessing (eddy current and motion correction)
dwifslpreproc dwi/dwi_den_unr.mif dwi/dwi_den_preproc.mif -pe_dir AP -rpe_none -readout_time 0.0342002 -eddy_options " --slm=linear --data_is_shelled" -nthreads 15

# Extract b0 and create mask for bias correction
dwiextract dwi/dwi_den_preproc.mif - -bzero | mrmath - mean dwi/mean_b0_AP.mif -axis 3
bet dwi/mean_b0_AP.nii.gz dwi/mean_b0_AP_bet.nii.gz -m -R -f 0.3

# Bias field correction
dwibiascorrect fsl dwi/dwi_den_preproc.mif dwi/dwi_den_preproc_unbiased.mif -mask dwi/mask_for_biascorrection.mif -bias dwi/bias.mif 
```

This step:
- Converts data to MRtrix format with gradient information
- Removes noise using PCA-based denoising
- Corrects for Gibbs ringing artifacts
- Applies eddy current and motion correction
- Performs bias field correction using FSL's implementation

### 2. Upsampling

```bash
# Upsample to 1.5mm isotropic resolution
mrgrid dwi/dwi_den_preproc_unbiased.mif regrid -vox 1.5 dwi/dwi_unbiased_upsampled.mif
```

Upsampling improves:
- Spatial resolution for better tractography
- Registration accuracy
- Atlas alignment precision

### 3. Response Function Estimation with DWI Masking

```bash
# Estimate response functions using Dhollander algorithm
dwi2response dhollander dwi/dwi_unbiased_upsampled.mif dwi/wm.txt dwi/gm.txt dwi/csf.txt -voxels dwi/voxels.mif

# Create DWI-based mask
dwi2mask dwi/dwi_unbiased_upsampled.mif dwi/mask_up.mif

# Multi-shell multi-tissue constrained spherical deconvolution
dwi2fod msmt_csd dwi/dwi_unbiased_upsampled.mif -mask dwi/mask_up.mif dwi/wm.txt dwi/wmfod_up.mif dwi/gm.txt dwi/gmfod_up.mif dwi/csf.txt dwi/csffod_up.mif 

# Normalize FODs across tissues
mtnormalise dwi/wmfod_up.mif dwi/wmfod_norm_up.mif dwi/gmfod_up.mif dwi/gmfod_norm_up.mif dwi/csffod_up.mif dwi/csffod_norm_up.mif -mask dwi/mask_up.mif 
```

Key features:
- **Dhollander algorithm**: Automatically estimates response functions for WM, GM, and CSF
- **DWI masking**: Uses mask derived directly from diffusion data
- **MSMT-CSD**: Resolves crossing fibers using multi-tissue information
- **Intensity normalization**: Ensures consistent FOD amplitudes

### 4. 5TT Generation and Coregistration

```bash
# Generate 5-tissue-type segmentation
5ttgen fsl dwi/T1.mif dwi/5tt_nocoreg.mif -nthreads 15

# Extract mean b0 for coregistration
dwiextract dwi/dwi_unbiased_upsampled.mif - -bzero | mrmath - mean dwi/mean_b0_processed_up.mif -axis 3

# Coregister T1 to DWI space using FLIRT
flirt -in dwi/mean_b0_processed_up.nii.gz -ref dwi/5tt_vol0.nii.gz -interp nearestneighbour -dof 6 -omat dwi/diff2struct_fsl_up.mat

# Transform 5TT image to DWI space
transformconvert dwi/diff2struct_fsl_up.mat dwi/mean_b0_processed_up.nii.gz dwi/5tt_nocoreg.nii.gz flirt_import dwi/diff2struct_mrtrix_up.txt 
mrtransform dwi/5tt_nocoreg.mif -linear dwi/diff2struct_mrtrix_up.txt -inverse dwi/5tt_coreg_up.mif

# Create GM/WM boundary seed region
5tt2gmwmi dwi/5tt_coreg_up.mif dwi/gmwmSeed_coreg_up.mif
```

This step:
- Creates anatomical tissue segmentation (cortical GM, subcortical GM, WM, CSF, pathological)
- Registers structural and diffusion images
- Generates seeding interface at GM/WM boundary

### 5. Streamline Generation

**Duration: ~1-2 hours**

```bash
# Generate 10 million streamlines
tckgen -act dwi/5tt_coreg_up.mif -backtrack -seed_gmwmi dwi/gmwmSeed_coreg_up.mif -nthreads 15 -maxlength 250 -cutoff 0.06 -select 10000k dwi/wmfod_norm_up.mif dwi/tracks_10M_up.tck 

# Apply SIFT2 filtering
tcksift2 -act dwi/5tt_coreg_up.mif -out_mu dwi/sift_mu_up.txt -out_coeffs dwi/sift_coeffs_up.txt dwi/tracks_10M_up.tck dwi/wmfod_norm_up.mif dwi/sift_1M_up.txt 
```

Tractography parameters:
- **ACT (Anatomically-Constrained Tractography)**: Uses tissue segmentation to guide streamlines
- **Backtracking**: Allows streamlines to backtrack when encountering anatomical barriers
- **GM/WM seeding**: Seeds streamlines at the gray matter-white matter interface
- **10 million streamlines**: High density for robust connectivity estimation
- **SIFT2**: Provides biologically meaningful streamline weights

### 6. Connectome Creation

**Duration: ~30-45 minutes**

```bash
# Register T1 to MNI space using ANTs
antsRegistrationSyN.sh -d 3 -f /home/fvanderhei/fsl/data/standard/MNI152_T1_1mm_brain.nii.gz -m dwi/skullstripped_T1w.nii.gz -o dwi/T1_to_MNI -n 15

# Transform atlases from MNI to subject T1 space
antsApplyTransforms -d 3 -i /home/fvanderhei/data/Gordon_Parcels.nii -r dwi/skullstripped_T1w.nii.gz -o dwi/Gordon_Parcels_T1w_space.nii.gz -n NearestNeighbor -t dwi/T1_to_MNI1InverseWarp.nii.gz -t [dwi/T1_to_MNI0GenericAffine.mat,1] -v

# Transform atlases to DWI space
mrtransform dwi/Gordon_Parcels_T1w_space.nii.gz -linear dwi/diff2struct_mrtrix_up.txt -inverse dwi/Gordon_Parcels_DWI_space.nii.gz

# Upsample atlases to match DWI resolution
mrgrid dwi/Gordon_Parcels_DWI_space.nii.gz regrid dwi/dwi_unbiased_upsampled.mif dwi/Gordon_Parcels_DWI_upsampled.nii.gz -interp nearest

# Create connectome matrices
tck2connectome -assignment_radial_search 4 -symmetric -zero_diagonal -scale_invnodevol -tck_weights_in dwi/sift_1M_up.txt dwi/tracks_10M_up.tck dwi/Gordon_Parcels_DWI_upsampled.nii.gz dwi/Gordon_parcels_DWImask.txt -out_assignment dwi/assignments_gordon_DWImask.csv
```

The pipeline processes four different brain atlases:
- **Gordon Parcels**: 333 cortical and subcortical regions
- **BN Atlas**: Brainnetome atlas with 246 regions
- **Glasser Parcels**: HCP multi-modal parcellation (360 regions)
- **Seitzman Parcels**: 300 ROIs including subcortical structures

Connectome features:
- **Radial search**: 4mm search radius for streamline-ROI assignment
- **Symmetric matrices**: Ensures undirected connectivity
- **Node volume scaling**: Accounts for regional size differences
- **SIFT2 weighting**: Uses optimized streamline weights

## Output Files

### Primary Connectome Matrices
Located in the working directory (`/home/fvanderhei/data/CC110056_tractography_dwimask_complete/dwi/`):

- `Gordon_parcels_DWImask.txt` - 333×333 connectivity matrix (Gordon parcellation)
- `BN_Atlas_DWImask.txt` - 246×246 connectivity matrix (Brainnetome atlas)
- `Glasser_parcels_DWImask.txt` - 360×360 connectivity matrix (Glasser parcellation)
- `Seitzman_parcels_DWImask.txt` - 300×300 connectivity matrix (Seitzman parcellation)

### Assignment Files
- `assignments_gordon_DWImask.csv` - Streamline-to-ROI assignments for Gordon atlas
- `assignments_BN_DWImask.csv` - Streamline-to-ROI assignments for BN atlas
- `assignments_glasser_DWImask.csv` - Streamline-to-ROI assignments for Glasser atlas
- `assignments_Seitzman_DWImask.csv` - Streamline-to-ROI assignments for Seitzman atlas

### Quality Control Files
- `dwi/noise.mif` - Estimated noise map from denoising
- `dwi/bias.mif` - Estimated bias field
- `dwi/sift_mu_up.txt` - SIFT2 proportionality coefficient
- `dwi/voxels.mif` - Response function estimation voxels

### Intermediate Processing Files
- `dwi/wmfod_norm_up.mif` - Normalized white matter FODs
- `dwi/5tt_coreg_up.mif` - 5-tissue-type segmentation in DWI space
- `dwi/gmwmSeed_coreg_up.mif` - GM/WM interface seeding mask

## Usage

1. **Set up paths**: Modify the source directory paths in the script to match your data location
2. **Verify prerequisites**: Ensure all required software is installed and atlas files are available
3. **Run the script**: Execute the bash script with appropriate permissions
4. **Monitor progress**: The script includes progress messages and typical duration estimates
5. **Check outputs**: Verify connectome matrices and quality control files

**Total estimated runtime**: 2-4 hours depending on hardware specifications.

## References

- [MRtrix3 Documentation](https://mrtrix.readthedocs.io/)
- [FSL Documentation](https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/)
- [ANTs Documentation](http://stnava.github.io/ANTs/)
- [Multi-Shell Multi-Tissue CSD](https://doi.org/10.1016/j.neuroimage.2014.07.061)
- [SIFT2 Paper](https://doi.org/10.1016/j.neuroimage.2015.05.039)
- [Anatomically-Constrained Tractography](https://doi.org/10.1016/j.neuroimage.2012.06.005)
- [Dhollander Response Function](https://doi.org/10.1016/j.neuroimage.2019.116017)