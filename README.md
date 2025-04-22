# MRtrix3 Preprocessing Pipeline

This repository contains scripts and documentation for preprocessing diffusion MRI data using MRtrix3.

## Overview

This pipeline processes diffusion-weighted imaging (DWI) data using MRtrix3 tools, including:
- File format conversion
- Noise removal
- Gibbs ringing correction
- Preprocessing with FSL's eddy tool

## Prerequisites

- Docker
- MRtrix3 Docker image
- Raw diffusion MRI data (NIfTI format with corresponding bvec/bval files)

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

## Next Steps

After preprocessing, you can continue with:
- Creating a brain mask
- Fitting diffusion tensor models
- Fiber orientation distribution analysis
- Tractography

## References

- [MRtrix3 Documentation](https://mrtrix.readthedocs.io/)
- [FSL eddy Documentation](https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/eddy)
