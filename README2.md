# MRtrix3 Diffusion MRI Pipeline
This repository contains scripts and documentation for processing diffusion MRI data using MRtrix3, including preprocessing, fiber orientation distribution analysis, and tractography.

## Table of Contents
- [Overview](#overview)
  - [Preprocessing](#preprocessing)
  - [Analysis](#analysis)
  - [Prerequisites](#prerequisites)
- [Preprocessing Steps](#preprocessing-steps)
  1. [Start Docker Container](#1-start-docker-container)
  2. [Navigate to Subject Directory](#2-navigate-to-subject-directory)
  3. [List Files](#3-list-files)
  4. [Convert DWI Data Format](#4-convert-dwi-data-format)
  5. [Rename Files for Consistency](#5-rename-files-for-consistency)
  6. [Examine the DWI Data](#6-examine-the-dwi-data)
  7. [Check Image Dimensions](#7-check-image-dimensions)
  8. [Verify Gradient Table Size](#8-verify-gradient-table-size)
  9. [Denoise the DWI Data](#9-denoise-the-dwi-data)
  10. [Remove Gibbs Ringing Artifacts](#10-remove-gibbs-ringing-artifacts)
  11. [Preprocess DWI with FSL Integration](#11-preprocess-dwi-with-fsl-integration)
  12. [Bias Field Correction](#12-bias-field-correction)
  13. [Generate Brain Mask](#13-generate-brain-mask)
- [Advanced Analysis Steps](#advanced-analysis-steps)
  1. [Fiber Orientation Distribution (FOD) Analysis](#1-fiber-orientation-distribution-fod-analysis)
  2. [Anatomical Image Processing & Registration](#2-anatomical-image-processing--registration)
  3. [Tractography Generation](#3-tractography-generation)
  4. [FreeSurfer Cortical Reconstruction](#4-freesurfer-cortical-reconstruction)
- [References](#references)

## Overview

This pipeline includes:

### Preprocessing
- File format conversion
- Noise removal
- Gibbs ringing correction
- Preprocessing with FSL's eddy tool
- Bias field correction
- Brain mask generation

### Analysis
- Fiber Orientation Distribution (FOD) estimation
- Multi-tissue Constrained Spherical Deconvolution
- Anatomically-Constrained Tractography (ACT)
- Structural connectivity analysis

## Prerequisites

- Docker
- MRtrix3 Docker image
- FSL software package
- FreeSurfer (for cortical reconstruction)
- Raw diffusion MRI data (NIfTI format with corresponding bvec/bval files)
- T1-weighted anatomical images

## Preprocessing Steps

### 1. Start Docker Container

```bash
docker run -it --rm -v "/path/to/your/data":/data mrtrix3/mrtrix3
```

This command:
- Starts an interactive (`-it`) Docker container
- Automatically removes the container when finished (`--rm`)
- Mounts your local data directory to `/data` in the container
- Uses the official MRtrix3 Docker image

### 2. Navigate to Subject Directory

```bash
cd /data/Subject1
```

Changes to the subject-specific directory within the mounted data volume.

### 3. List Files

```bash
ls
```

Displays the contents of the current directory to verify your files.

### 4. Convert DWI Data Format

```bash
mrconvert sub-CC110037_dwi.nii.gz sub-CC110037_dwi.mif -fslgrad sub-CC110037_dwi.bvec sub-CC110037_dwi.bval
```

- Converts the diffusion data from NIfTI format (`.nii.gz`) to MRtrix format (`.mif`)
- The `-fslgrad` option imports the gradient information (directions and b-values) from FSL format files
- `.bvec` contains the gradient directions
- `.bval` contains the b-values

MRtrix's `.mif` format stores all necessary information in a single file, which is more convenient for processing.

### 5. Rename Files for Consistency

```bash
mv sub-CC110037_dwi.bvec Subject1_AP.bvec
mv sub-CC110037_dwi.bval Subject1_AP.bval
mv sub-CC110037_dwi.nii.gz Subject1_dwi.nii.gz
mv sub-CC110037_dwi.json Subject1_dwi.json
```

These commands rename the original files to follow a consistent naming convention:
- `AP` indicates the phase-encoding direction (Anterior-Posterior)
- Using subject-specific prefixes makes the workflow more maintainable

### 6. Examine the DWI Data

```bash
mrinfo Subject1_dwi.mif
```

Displays comprehensive information about the DWI dataset, including:
- Dimensions
- Voxel size
- Data type
- Gradient table information
- Image orientation

### 7. Check Image Dimensions

```bash
mrinfo -size Subject1_dwi.mif | awk '{print $4}'
```

Extracts and displays the number of volumes (diffusion directions) from the image dimensions.

### 8. Verify Gradient Table Size

```bash
awk '{print NF; exit}' Subject1_AP.bvec
awk '{print NF; exit}' Subject1_AP.bval
```

These commands count the number of entries in the gradient direction (`.bvec`) and b-value (`.bval`) files to ensure they match the number of volumes in the data.

### 9. Denoise the DWI Data

```bash
dwidenoise Subject1_dwi.mif Subject1_den.mif -noise noise.mif
```

- Applies principal component analysis (PCA) based denoising to improve signal-to-noise ratio
- Outputs the denoised data to `Subject1_den.mif`
- The `-noise` option saves the estimated noise map to `noise.mif` for quality control

### 10. Remove Gibbs Ringing Artifacts

```bash
mrdegibbs Subject1_den.mif Subject1_den_unr.mif
```

Reduces Gibbs ringing artifacts (oscillations near sharp boundaries) that occur due to finite sampling in k-space.

### 11. Preprocess DWI with FSL Integration

```bash
dwifslpreproc Subject1_den.mif Subject1_den_preproc.mif -nocleanup -rpe_none -pe_dir AP -eddy_options " --slm=linear --data_is_shelled"
```

This command performs preprocessing using FSL's `eddy` tool:
- Input: `Subject1_den.mif` (denoised data)
- Output: `Subject1_den_preproc.mif` (preprocessed data)
- `-nocleanup`: Keeps intermediate files (useful for debugging)
- `-rpe_none`: Indicates no reverse phase-encoding data is available
- `-pe_dir AP`: Specifies the phase-encoding direction as Anterior-Posterior
- `--slm=linear`: Uses a linear model for slice-to-volume motion correction
- `--data_is_shelled`: Indicates that the data was acquired with a multi-shell scheme

This step corrects for:
- Susceptibility-induced distortions
- Eddy current-induced distortions
- Subject motion

### 12. Bias Field Correction

```bash
dwibiascorrect ants Subject1_den_preproc.mif Subject1_den_preproc_unbiased.mif -bias bias.mif
```

This command corrects for intensity inhomogeneities (bias fields) in the DWI data using ANTs N4 bias correction:
- Input: `Subject1_den_preproc.mif` (motion and eddy current corrected data)
- Output: `Subject1_den_preproc_unbiased.mif` (bias field corrected data)
- The `-bias` option saves the estimated bias field to `bias.mif` for quality control

Bias field correction is essential for:
- Accurate intensity-based analysis
- Proper tissue segmentation
- Consistent quantitative measurements across the brain

### 13. Generate Brain Mask

```bash
dwi2mask Subject1_den_preproc_unbiased.mif mask.mif
```

Creates a binary brain mask to restrict analysis to brain tissue only:
- Input: `Subject1_den_preproc_unbiased.mif` (bias corrected data)
- Output: `mask.mif` (binary brain mask)

The brain mask:
- Excludes non-brain tissue (skull, scalp, air)
- Improves computational efficiency by focusing analysis on brain voxels
- Reduces noise from background regions
- Is essential for subsequent analysis steps including FOD estimation

## Advanced Analysis Steps

After preprocessing, the pipeline continues with advanced diffusion MRI analysis:

### 1. Fiber Orientation Distribution (FOD) Analysis

```bash
# Estimate response functions for different tissue types using dhollander algorithm
dwi2response dhollander Subject2_den_preproc_unbiased.mif wm.txt gm.txt csf.txt -voxels voxels.mif

# Estimate FODs using multi-shell, multi-tissue constrained spherical deconvolution
dwi2fod msmt_csd Subject2_den_preproc_unbiased.mif -mask mask.mif \
    wm.txt wmfod.mif gm.txt gmfod.mif csf.txt csffod.mif

# Create a 3-tissue volume fraction image
mrconvert -coord 3 0 wmfod.mif - | mrcat csffod.mif gmfod.mif - vf.mif

# Perform multi-tissue normalization
mtnormalise wmfod.mif wmfod_norm.mif gmfod.mif gmfod_norm.mif \
    csffod.mif csffod_norm.mif -mask mask.mif
```

These commands:
- Estimate response functions for white matter, gray matter, and CSF
- Perform multi-shell, multi-tissue constrained spherical deconvolution to get FODs
- Create volume fraction maps for visualization
- Normalize FOD intensities across subjects for group analysis

### 2. Anatomical Image Processing & Registration

```bash
# Convert T1w image to MRtrix format
mrconvert sub-CC110045_T1w.nii t1.mif

# Generate 5-tissue-type segmentation for anatomically constrained tractography
5ttgen fsl T1.mif 5tt_nocoreg.mif

# Extract and average b=0 volumes from DWI data
dwiextract Subject2_den_preproc_unbiased.mif - -bzero | mrmath - mean mean_b0.mif -axis 3

# Convert files to NIfTI format for FSL registration
mrconvert mean_b0.mif mean_b0.nii.gz
mrconvert 5tt_nocoreg.mif 5tt_nocoreg.nii.gz

# Extract first volume from 5tt image for registration
fslroi 5tt_nocoreg.nii.gz 5tt_vol0.nii.gz 0 1

# Register diffusion to structural image
flirt -in mean_b0.nii.gz -ref 5tt_vol0.nii.gz -interp nearestneighbour -dof 6 -omat diff2struct_fsl.mat

# Convert transformation matrix from FSL to MRtrix format
transformconvert diff2struct_fsl.mat mean_b0.nii.gz 5tt_nocoreg.nii.gz flirt_import diff2struct_mrtrix.txt

# Apply transformation to 5tt image to align with diffusion space
mrtransform 5tt_nocoreg.mif -linear diff2struct_mrtrix.txt -inverse 5tt_coreg.mif

# Extract gray matter-white matter interface for seeding tractography
5tt2gmwmi 5tt_coreg.mif gmwmSeed_coreg.mif
```

These steps:
- Process the T1-weighted anatomical image
- Register the diffusion and structural data
- Extract tissue interfaces for tractography seeding

### 3. Tractography Generation

```bash
# Generate 10 million streamlines using anatomically constrained tractography
tckgen -act 5tt_coreg.mif -backtrack -seed_gmwmi gmwmSeed_coreg.mif \
    -nthreads 8 -maxlength 250 -cutoff 0.06 -select 10000000 \
    wmfod_norm.mif tracks_10M.tck

# Apply SIFT2 to obtain streamline weights for more biologically accurate connectivity analysis
tcksift2 -act 5tt_coreg.mif -out_mu sift_mu.txt -out_coeffs sift_coeffs.txt \
    -nthreads 8 tracks_10M.tck wmfod_norm.mif sift_1M.txt
```

This generates:
- 10 million anatomically-constrained tractography streamlines
- SIFT2 weights to adjust for reconstruction biases

### 4. FreeSurfer Cortical Reconstruction

```bash
# Set FreeSurfer subjects directory
SUBJECTS_DIR=$(pwd)

# Run FreeSurfer's cortical reconstruction pipeline
recon-all -i sub-CC110045_T1w.nii -s sub-CON02_recon -all
```

FreeSurfer's `recon-all` command:
- Performs cortical surface reconstruction
- Creates cortical parcellations
- Enables later connectome generation with anatomical ROIs

## References

- [MRtrix3 Documentation](https://mrtrix.readthedocs.io/)
- [FSL Documentation](https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/)
- [FreeSurfer Documentation](https://surfer.nmr.mgh.harvard.edu/fswiki)
- [Multi-Tissue CSD Paper](https://doi.org/10.1016/j.neuroimage.2014.07.061)
- [SIFT2 Paper](https://doi.org/10.1016/j.neuroimage.2015.05.039)
- [Anatomically-Constrained Tractography Paper](https://doi.org/10.1016/j.neuroimage.2012.06.005)