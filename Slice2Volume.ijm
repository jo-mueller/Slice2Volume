/*
 * Author: Johannes Müller, johannes.mueller@ukdd.de
 * LICENSE
 */

//clean up
close("*");
if (isOpen("Progress")) {
	
close("Progress");
}

//================================== CONFIG =====================

#@ String (visibility=MESSAGE, value="Elastix parameters", required=false) a
#@ File (label="Elastix parameter file", style="file") elastix_parameters
#@ File (label="Elastix installation directory", style="directory") Elastix_dir

#@ String (visibility=MESSAGE, value="Input data", required=false) b
#@ File (label="Microscopy input", style="directory") dir_2D
#@ File (label="Target Volume input", style="file") TrgVolume

#@ String (visibility=MESSAGE, value="File structure", required=false) d
#@ String (label="Subdirectory structure", value="") subdir_path
#@ String (label="Filename ID string", value="") ID_string

#@ String (visibility=MESSAGE, value="Geometric parameters", required=false) c
#@ Integer (label="Distance between subsequent sections (microns)", value = 150) d_slice
#@ Integer (label="Target volume voxel size (microns)", value = 40) d_Volume
#@ Integer (label="Discarded tissue (microns)") shift

#@ String (visibility=MESSAGE, value="Preprocessing parameters", required=false) d
#@ Integer (label="Histo Outline smoothing degree", value=1) n_smoothing_hist
#@ Integer (label="Volume outline smoothing degree", value=3) n_smoothing_vol
#@ String (label="Exclude values/labels from Volume", value = "102, 337-350") exclude_labels
#@ String (label="Inital input rotation (CW, degrees)", value = "0") init_rotation
#@ Boolean (label = "Batch mode?", value=true) use_batch
#@ String (label = "Symmetry correction?", choices={"None", "X-Axis", "Y-Axis"}, style="radioButtonHorizontal") symmetry_guard_axis


// file path format
if (!endsWith(dir_2D, "/") && !endsWith(dir_2D, "\\")) {
	dir_2D = dir_2D + "\\";
}

if (use_batch) {
	setBatchMode(true);
}

// Global Variables
var InputFormatChecked = false;		// flag for the dimensionality check of the 2D input data
var InputSizeChecked = false;		// flag for the image size check of the 2D input data

var DownSamplingFactor = 1.0;		// Downsampling factor for further use
var Width_Large = 0.0;				// Keep quotients that define downsampling factor to be safe
var Width_Small = 0.0;				// DownSamplingFactor := Width_Small/Width_Large

var MaskSlice = 1;					// Default value for 2D slice to be masked
var DataSlice = 1;					// Default value for 2D slice to be transformed
var Correction_Angle = 0;			// Correctional angle to make volume symmetric along a defined axis. 

var OverviewTable = "OverviewTable"; // Log box that lists the assignment of each 2D plane in the 3D volume

//================================== MAIN =====================


function main(){

	// Local Variables
	Output_Stack = "Output_Stack";

	// Make overview
	makeOverviewTable();

	// Make directories
	outdir = createDirectories(dir_2D, TrgVolume);
	dir_trafo = outdir + "trafo\\";
	dir_res = outdir + "results\\";
	
	
	

	// First: Process the volumetric input and make corresponding output image
	// Also: Put the windows on screen so they're nicely displayed next to each other
	Volume = LoadAndSegmentAtlas(TrgVolume, exclude_labels, n_smoothing_vol);

	// Run Symmetry guard check
	Volume = SymmetryGuard_Detect(Volume, symmetry_guard_axis);
	
	getDimensions(width, height, channels, slices, frames);
	setLocation(0, 200, width, height);
	newImage(Output_Stack, "32-bit black", getWidth(), getHeight(), nSlices);
	setLocation(width, 200, width, height);
	
	// Second: Determine boundaries of Volume image along the z-direction
	boundaries = TopBottomLayer(Volume);
	
	//Returns an array containing the names of the files from the 2D input
	ListOfImages = getImages(dir_2D, subdir_path, ID_string);

	// Timer variables
	times = newArray();
	T = 0;

	// Iterate over all input files
	for (i = 0; i < ListOfImages.length; i++) {

		// Start timer
		t0 = getTime();

		// Find corresponding slice in Volume based on filename
		depth = findLocationInVol(	ListOfImages[i],	// currently processed image
									Volume,				// Target volume
									Output_Stack,		// Output stack
									boundaries,			// mask boundaries along z-direction
									shift,				// amount of discarded tissue in microns
									2,					// number of samples per carrier
									d_slice,			// slice distance of histological sections
									d_Volume);			// slice distance of volumetric image
		
		// open 2D image and split into mask and data
		Open2DImage(ListOfImages[i], Volume);
		MovingMask = "MovingMask";
		MovingData = "MovingData";
		MovingMask = GenerateMask(MovingMask, n_smoothing_hist);

		TargetMask = "TargetMask";

		// Save all images to trafo dir
		beautifyDisplay(width, height);
		selectWindow(MovingMask); 	run("32-bit"); 	saveAs("tif", dir_trafo + MovingMask);	
		selectWindow(MovingData);	run("32-bit"); 	saveAs("tif", dir_trafo + MovingData);
		selectWindow(TargetMask);	run("32-bit"); 	saveAs("tif", dir_trafo + TargetMask);

		// Do registration
		TrnsfmdImg = RegAndTraf(Elastix_dir, elastix_parameters, 	// elastix input
								dir_trafo + MovingMask,				// Moving Mask path
								dir_trafo + MovingData,				// Moving Data path
								dir_trafo + TargetMask,				// Target Mask path
								dir_trafo, dir_res,					// working directory and outout directory
								ListOfImages[i]);					// currently processed input image

		// Paste to output stack
		PasteToStack(TrnsfmdImg, Output_Stack, depth);

		// Print to protocol
		print(OverviewTable, i+1+"\t"+ListOfImages[i]+"\t"+(depth - boundaries[0])*d_Volume + "microns\t"+depth);
		close(TargetMask + ".tif"); close(MovingData + ".tif"); close(MovingMask + ".tif");

		// Timer
		dt = getTime() - t0;
		times = Array.concat(times, dt);
		T += dt;
	}

	// Timer output
	Array.getStatistics(times, min, max, mean, stdDev);
	print("Total time taken: " + T/1000 + "s, Time per slice: " + mean/1000 + "s");
	
	// Post-process: Interpolate missing slices
	Interpolated_Output = Interpolate_Stack(Output_Stack, boundaries);
	
	// Apply Symmetry guard
	if (symmetry_guard_axis != "None") {
		Interpolated_Output = SymmetryGuard_Apply(Interpolated_Output, symmetry_guard_axis);
		Output_Stack = SymmetryGuard_Apply(Output_Stack, symmetry_guard_axis);
	}

	// Save Output
	SaveOutput(Output_Stack, Interpolated_Output, dir_res);
}

//================================== FUNCTIONS =====================

function SymmetryGuard_Apply(image, axis){
	/*
	 * Applies a previously determined correction rotation along a defined <axis>
	 * to the given input Volume <Image>.
	 */

	selectWindow(image);
	if (axis == "Y-Axis") {
		run("Reslice [/]...", "start=Top");
		vol = getTitle();
	}
	
	if (axis == "X-Axis") {
		run("Reslice [/]...", "output=1.000 start=Left");
		vol = getTitle();
	}
	close(image);

	selectWindow(vol);
	// Apply rotation to resliced image	
	if (Correction_Angle >= 0) {
		run("Rotate... ", "angle=-" + Correction_Angle + " grid=1 interpolation=None fill stack");	
	} else {
		run("Rotate... ", "angle=" + Correction_Angle + " grid=1 interpolation=None fill stack");	
	}

	// return to original axis configuration
	if (axis == "Y-Axis") {
		run("Reslice [/]...", "output=1.000 start=Top");
		output = getTitle();
	}
	if (axis == "X-Axis") {
		run("Reslice [/]...", "output=1.000 start=Left");
		output = getTitle();
	}
	close(vol);
	selectWindow(output);
	rename(image);
	return image;
}

function SymmetryGuard_Detect(Volume, axis){
	/*
	 * This function checks whether the binary input <Volume> is symmetrical along a
	 * defined symmetry plane that is not (!) the image plane. The symmetry plane
	 * of interest is defined by the <axis> parameter.
	 */

	// First test if symmetry guard was activated at all
	if (axis == "None") {
		return Volume;
	}

	if (axis == "Y-Axis") {
		run("Reslice [/]...", "output=1.000 start=Top avoid");
		vol = getTitle();
	}
	if (axis == "X-Axis") {
		run("Reslice [/]...", "output=1.000 start=Left avoid");
		vol = getTitle();
	}
	close(Volume);
	selectWindow(vol);
	
	// Prep measurement
	run("Set Measurements...", "area mean display redirect=None decimal=2");
	BBox = "BBox";
	BBox_rot = "BBox_rotated";
	
	// Have binary atlas selected and create maximum intensity projection.
	// Then crop part of image that holds information
	selectWindow(vol);
	run("Z Project...", "projection=[Max Intensity]");
	Projection = getTitle();
	run("Select Bounding Box");
	run("Duplicate...", "title=" + BBox);

	// predefined range of acceptable rotation angles
	alpha_min = -10;
	alpha_max = 10;
	N_angles = 40;
	symm_results = newArray(N_angles);
	angles = newArray(N_angles);

	// iteratively rotate images by a range of angles.
	// Then evaluate symmetry for every angle
	for (i = 0; i < N_angles; i++) {
		alpha = alpha_min + i*(alpha_max - alpha_min)/N_angles;
		selectWindow(BBox);
		run("Duplicate...", "title=" + BBox_rot);
		run("Rotate... ", "angle=" + alpha + " grid=1 interpolation=None fill");
		
		// evaluate and store symmetry descriptors
		symm = eval_symmetry(BBox_rot);
		symm_results[i] = symm;
		angles[i] = alpha;
		close(BBox_rot);
	}
	close(BBox);
	close(BBox_rot);
	close(Projection);

	// Find best angle and return
	threshold = 1000000;
	index = 0;
	
	for (i = 0; i < angles.length; i++){
		if (symm_results[i] < threshold) {
			threshold = symm_results[i];
			index = i;
		}
	}

	// Apply rotation
	selectWindow(vol);
	Correction_Angle = angles[index];
	print("Rotating volume by angle=" + d2s(Correction_Angle, 2) + " along " + axis);
	run("Rotate... ", "angle=" + d2s(Correction_Angle, 2) + " grid=1 interpolation=None fill stack");

	// Undo reslice according to direction settings from above and return.
	if (axis == "Y-Axis") {
		run("Reslice [/]...", "output=1.000 start=Top avoid");
		output = getTitle();
	}
	if (axis == "X-Axis") {
		run("Reslice [/]...", "output=1.000 start=Left avoid");
		output = getTitle();
	}
	output = getTitle();
	rename(Volume);
	close(vol);
	
	return Volume;
}

function eval_symmetry(image){
	/*
	 * Evaluates the symmetry of a given <image> along the LR-direction.
	 * Does so by flipping the image horizontally and calculating the difference between the 
	 * flipped/unflipped image
	 */
	
	// Make mirrored copy
	selectWindow(image);
	mirrored = image + "_mirrored";
	run("Duplicate...", "title="+mirrored);

	// flip mirror
	selectWindow(mirrored);
	run("Flip Horizontally");

	// calc difference
	imageCalculator("Difference create 32-bit", image, mirrored);
	output = getTitle();
	selectWindow(output);
	run("Measure");
	mean = getResult("Mean", nResults - 1);

	// clean up and return
	close(mirrored);
	close(output);
	return mean;
}

function SaveOutput(V, V_int, outdir){
	/*
	 * Saves all relevant settings and output to a separate directory <outdir>
	 * Store are: Raw output volume <V> and interpolated volume <V_int>
	 */

	// add ID string to name if it was set
	name_raw = "OutputStack";
	name_int = "OutputStack_interpolated";
	if (ID_string != "") {
		name_raw += "_" + ID_string;
		name_int += "_" + ID_string;
	}

	selectWindow(V);
	saveAs(".tif", outdir + name_raw);
	
	selectWindow(V_int);
	saveAs(".tif", outdir + name_raw);
	saveAs(".tif", outdir + name_int);
	
	selectWindow("OverviewTable");
	saveAs("Text", outdir + "SliceAssignment_Overview");
	
	f = File.open(outdir + "S2V_LogFile.txt");
	
	print(f, "Input data:");
	print(f, "Input Volume:\t" + TrgVolume);
	print(f, "Microscopy input:\t" + dir_2D);
	print(f, "Subdir specification:\t" + subdir_path);
	print(f, "ID string:\t" + ID_string);
	
	print(f, "\nGeometric Parameters:");
	print(f, "Cut distance:\t" + d_slice);
	print(f, "Volume slice distance:\t" + d_Volume);
	print(f, "Discarded tissue:\t" + shift);

	print(f, "\nProcessing parameters:");
	print(f, "Histological outline smoothing:\t" + n_smoothing_hist);
	print(f, "Volumetric outline smoothing:\t" + n_smoothing_vol);
	print(f, "Initial rotation:\t" + init_rotation);
	print(f, "Downsampling factor:\t" + DownSamplingFactor + "\t" + Width_Small + "\t" + Width_Large);
	print(f, "Exluded fields from volume:\t" + exclude_labels);
	print(f, "Correction angle:\t" + Correction_Angle); 
	print(f, "Correction axis:\t" + symmetry_guard_axis); 
	close(f);	 
}

function Interpolate_Stack(Vol, zBoundaries) {
	/*
	 * Makes copy of input volume <Vol> and interpolates black slices in the regions between
	 * <zBoundaries[0]> and <zBoundaries[1]>. 
	 */

	int_outStack = "Interpolated_output_stack";
	selectWindow(Vol);
	run("Duplicate...", "title="+int_outStack+" duplicate");
	output = getTitle();

	selectWindow(Vol);
	run("Set Measurements...", "area_fraction display redirect=None decimal=2");

	 // iterate over all slices within boundaries
	 for (i = zBoundaries[0]; i < zBoundaries[1]; i++) {
	 	setSlice(i);

	 	run("Measure");										//run measure of ith slice
		area_fraction = getResult("%Area", nResults - 1);	//measure the percentage of nonzero pixels in the image

		//interpolate all black images
		if (area_fraction == 0){			//pick all black images
			
			//copy slice i-1				
			setSlice(i - 1);				//set last known non-black slice
			run("Duplicate...", "title=a slice");	//duplicate the slice
	
			selectWindow(output);	//select the damage_stack_int

			//loop to obtain the next non black slice and duplicate it
			for (k = 0; k < nSlices; k++) {
				
				if (i + k +1 == nSlices) {
					close("a");
					close("b");
					return int_outStack;
				}

				setSlice(i + k + 1);				//set slice i+k
				run("Measure");
				area_fraction = getResult("%Area", nResults - 1);

				// If next non-black slice is found: Count subsequent number of black slices
				if (area_fraction != 0) {
	
					run("Duplicate...", "title=b slice");	//duplicate the slice
	
					nblackslices = k + 1;			//number of black slices between two non black slices
					nwalls = nblackslices + 1;		//number of walls (zw. zwei bildern ist eine wall)
					break;
				}
			}
			
			//loop to fill all black slices (between "a" and "b") with info via weighting function
			for (k = 0; k < nblackslices; k++) {
			
				c1 = nwalls - k - 1;				//prefactor of slice "a"
				c2 = nwalls - c1;					//prefactor of slice "b"
					
				selectWindow("a");
				run("Multiply...", "value=&c1");
				selectWindow("b");
				run("Multiply...", "value=&c2");
	
				imageCalculator("Add create 32-bit", "a","b");	//create the average
				run("Divide...", "value=&nwalls");
				rename("c");										//rename it to "c"
	
	
				//insert the interpolated slice into damage stack
				selectWindow("c");					//select the interpolated slice "c"
				run("Copy");						//copy the slice
				selectWindow(int_outStack);		//select the damage_stack_int
				setSlice(i + k);					//set slice i + l
				run("Paste");						//paste the interpolated slice
		
				//Clean up
				close("c");     					//close the interpolated slice
	
				
				//undo changes of "a" and "b" for next slice
				selectWindow("a");
				run("Divide...", "value=&c1");
				selectWindow("b");
				run("Divide...", "value=&c2");
			
			}

			
			close("a");											//close "a"
			close("b");											//close "b"
			
		}
	}
	return int_outStack;
}

function beautifyDisplay(w, h){
	selectWindow(MovingMask);
	setLocation(2*width, 200, width, height);
	run("Create Selection");

	selectWindow(MovingData);
	run("Enhance Contrast", "saturated=0.35");
	setLocation(3*width, 200, width, height);
	run("Restore Selection");

	selectWindow(TargetMask);
	setLocation(4*width, 200, width, height);
}

function PasteToStack(image, V, k){
	/*
	 * Copies the contents of <image> and pastes them to slice <s> of Volume <V>
	 * Checks whether dimensions match.
	 */

	// Do dimension check
	selectWindow(image);
	s = getWidth() * getHeight();

	selectWindow(V);
	_s = getWidth() * getHeight();

	if (_s != s) {
		print("    ERROR: Transformed image doesn't match volume dimensions!");
		exit();
	}

	// Do the pasting
	selectWindow(image);
	run("Copy");
	selectWindow(V);
	setSlice(k);
	run("Paste");
	close(image);
	 
}

function RegAndTraf(Elastix_dir, param_file, MovImg, MovData, TrgImg, wdir, outdir, filename) {
	/*
	 * Call s elastix registration from <Elastix_dir> using parameter file <param_file> to co-align <MovMask> with <TrgMask>.
	 * The registration takes place in a working dir <wdir>, the results are stored in <outdir>.
	 * The resulting transformation will be used to call transformix with <MovData> as transformed image.
	 * The transformparameters will be stored under the name of <filename>
	 * 
	 * returns: image handle to transformed image
	 */

	wait(1000);
	print("    INFO: Moving image = " + MovImg);
	print("    INFO: Target image = " + TrgImg);
	TrgImg += ".tif";
	MovData += ".tif";
	MovImg += ".tif";

	// get a string that identifies this slice correctly
	filestring = replace(MovData, File.separator, "/");
	filestring = replace(filestring, ".tif", "_tif");
	filestring = replace(filestring, "-|/" , "_");

	filestring = split(filestring, "_");
	for (i = 0; i < filestring.length; i++) {
		if (filestring[i] == "Scene") {
			a = parseInt(filestring[i - 1]);
			b = parseInt(filestring[i + 1]);
			break;
		}
	}
	
	 // First, call elastix
	exec(Elastix_dir + "\\elastix.exe",	//elastix installation directory
		"-f", TrgImg, 	//set fixed image
		"-m", MovImg, 	//set moving image
		"-out", wdir, 	//set output directory
		"-p", param_file);	//directory of elastix parameters used for the transformation
		

	// Second, call transformix
	exec(Elastix_dir + "\\transformix.exe",	//elastix installation directory
		"-in", MovData, 	//set moving image
		"-out", wdir, 	//set output directory
		"-tp", wdir + "TransformParameters.0.txt");	//directory of elastix parameters used for the transformation

	// Save transformation file
	trafofile = wdir + IJ.pad(a, 4) + "_Scene_" + b + "_trafo.txt";
	trafofile_inv = wdir + IJ.pad(a, 4) + "_Scene_" + b + "_trafo_inverse.txt";
	File.copy(wdir + "TransformParameters.0.txt", trafofile);
	File.delete(wdir + "TransformParameters.0.txt");

	// Get inverse transformation by attempting to undo determined transformation with elastix
	// The inverse registration parameter file is stored in the same dir as the elastix parameters
	param_file_inv = File.getDirectory(param_file) + "invRegParameters.txt";
	exec(Elastix_dir + "\\elastix.exe",	// elastix installation directory
		"-f", MovData, 	// Fixed image = Moving image
		"-m", MovData, 	// Fixed image = Moving image
		"-out", wdir, 	// set output directory
		"-t0", trafofile, // previously determined trafo as initial trafo
		"-p", param_file_inv);	//directory of elastix parameters used for the transformation

	// Alter inverse trafofile so that it works properly:
	// First read original trafofile and generate (empty) copy
	lines = File.openAsString(wdir + "TransformParameters.0.txt");
	lines =  split(lines, "\n");
	f = File.open(trafofile_inv);

	// copy original trafofile line by line
	for (i = 0; i < lines.length; i++) {
		// replace initial transform with none
		if (matches(lines[i], ".*InitialTransform.*")) {
			print(f, "(InitialTransformParametersFileName \"NoInitialTransform\")");
			continue;
		}

		// copy other lines as they are
		print(f, lines[i]);
	}
	File.close(f);
	File.delete(wdir + "TransformParameters.0.txt");

	// Clean up a bit
	//File.copy(wdir + "TransformParameters.0.txt", trafofile_inv);  // rename inverse trafo
	File.delete(wdir + "elastix.log");
	File.delete(wdir + "transformix.log");
	files = getFileList(wdir);
	for (i = 0; i < files.length; i++) {
		if (matches(files[i], ".*IterationInfo.*")) {
			File.delete(wdir + files[i]);
		}
	}
	//File.delete(MovData);
	//File.delete(MovImg);
	//File.delete(TrgImg);	

	// Return result
	open(wdir + "result.tif");
	image = getTitle();
	return image;

	
}

function findLocationInVol(filename, Vol, OutStack, Vol_bounds, DistFromTop, SamplesPerCarrier, d_Cut, d_Vol){
	// Determines the location of the selected 2D file <filename> in the Volume image <Vol> based on an implicit file format.
	// The same location is set for the output volume <OutStack>.
	//
	// The file has to contain "..._XXXX_Scene_Y_.... to determine the correct location.
	// Other inputs: Discarded tissue <DistFromTop> in microns as well as Volume mask boundaries <Vol_bounds>, tissue cut distance <d_Cut>,
	// number of samples per object carrier and volume voxel size <d_Vol>

	// Returns: index of slice in Volume

	// First, reformat filestring and look for the "Scene" keyword
	filestring = replace(filename, File.separator, "/");
	filestring = replace(filestring, ".tif", "_tif");
	filestring = replace(filestring, "-|/" , "_");

	filestring = split(filestring, "_");
	for (i = 0; i < filestring.length; i++) {
		if (filestring[i] == "Scene") {
			a = parseInt(filestring[i - 1]);
			b = parseInt(filestring[i + 1]);
			break;
		}
	}

	// Explanation: 
	// (a-1): Sample carrier with number one is first carrier, aka carrier zero.
	// (b-1): Scene with number 1 is first scene, aka scene 0
	// SamplesPerCarrier*(a - 1) + (b-1): Total number of tissue sections that have been taken until this one
	// DistFromTop + d_Cut * (...): Absolute distance of this sample from top of organ
	depth = Vol_bounds[0] + DistFromTop/d_Vol + d_Cut * (SamplesPerCarrier * (a - 1) + (b-1))/d_Vol;
	depth = floor(depth);

	print("    INFO: Slice " + filename + " matches Volume slice #" + depth);

	// select propper slice and duplicate chosen slice
	selectWindow(OutStack);
	setSlice(depth);

	selectWindow(Vol);
	setSlice(depth);
	run("Duplicate...", "title=TargetMask duplicate range=" + depth + "-" + depth);
	return depth;
	
}


function GenerateMask(MaskedImage, N_Smooth){
	// Creates a binary mask from an input image <image>.
	// A bit of morphological post-processing is applied, based on the parameter <N_Smooth>.
	// High N-> lot of smoothing, low N -> less smoothing

	// Preprocess
	selectWindow(MaskedImage);
	run("Median...", "radius=4");

	// Restrict thresholding to non-zero area of image
	setThreshold(1,1E30);
	run("Create Selection");
	run("Enlarge...", "enlarge=-3 pixel");
	resetThreshold();	
	
	setAutoThreshold("Huang dark");	
	run("Convert to Mask");
	
	// Smooth
	DilateErode(N_Smooth);
	selectWindow(MaskedImage);
	run("Fill Holes");
	return MaskedImage;
}

function Open2DImage(fname, Vol) {
	// open 2D image from <fname> and do a couple of checks to provide a correct mask for registration.
	// For once, layers of the input image are checked and the size of the 2D plane is compared to the <volume> image
	
	// look at Volume
	selectWindow(Vol);
	w = getWidth();
	h = getHeight();

	open(fname);
	image = getTitle();

	// Apply initial rotation if option was set
	// Decompose into rotations of 90 degree
	n_rotations = round(init_rotation/90.0);
	
	for (i = 0; i < abs(n_rotations); i++) {
		if (n_rotations >0) {
			run("Rotate 90 Degrees Right");
		}
		if (n_rotations <0) {
			run("Rotate 90 Degrees Left");
		}
	}

	// first, check if images has mutiple layers. If so, user has to choose, which is maskable and which should be transformed
	if (nSlices > 1 && (InputFormatChecked == false)) {
		Dialog.createNonBlocking("User input required");
		Dialog.addMessage("The input image seems to have multiple layers.\nWhich of these is maskable (Mask slice) and which should be transformed (data slice)?");
		Dialog.addNumber("Mask slice", 1);
		Dialog.addNumber("Data slice", 1);
		Dialog.show();

		MaskSlice = Dialog.getNumber();
		DataSlice = Dialog.getNumber();
		InputFormatChecked = true;	// check this only once and keept setting throughout script.		
	}

	// second, check the image size dimension and offer downsampling.
	// Criterion: 2D image has to be 10x as large as the corresponding volume plane
	selectWindow(image);
	w_i = getWidth();
	h_i = getHeight();
	// Downsampling necessary?
	if (!InputSizeChecked && (w_i * h_i > 10* w * h)) {
		DoDownsampling = getBoolean("The input image ("+d2s(w_i, 0) + "x" + d2s(h_i,0) +") is much larger than the target volume ("+d2s(w, 0) + "x" + d2s(h,0) +").\n"+
									"Proceed with downsampled image?");
		// If desired, adjust settings for downsampling in all following images
		if (DoDownsampling) {

			// get a copy of bounding retangle in volume mask to estimate difference in size
			selectWindow(Vol);
			run("Duplicate...", "title=Temp");
			selectWindow("Temp");
			run("Select Bounding Box");
			Roi.getBounds(x, y, width, height);
			close("Temp");

			// Set Downsampling parameters for further use and log
			DownSamplingFactor = width/w_i;
			Width_Large = w_i;
			Width_Small = width;
		}
		InputSizeChecked = true;
	}
	
	// Upscaling necessary?
	if (!InputSizeChecked && (w_i * h_i < 0.3* w * h)) {
		DoDownsampling = getBoolean("The input image ("+d2s(w_i, 0) + "x" + d2s(h_i,0) +") is much smaller than the target volume ("+d2s(w, 0) + "x" + d2s(h,0) +").\n"+
									"Proceed with upscaled images?");
		// If desired, adjust settings for downsampling in all following images
		if (DoDownsampling) {

			// get a copy of bounding retangle in volume mask to estimate difference in size
			selectWindow(Vol);
			run("Duplicate...", "title=Temp");
			selectWindow("Temp");
			run("Select Bounding Box");
			Roi.getBounds(x, y, width, height);
			close("Temp");

			// Set upscaling parameters for further use and log
			DownSamplingFactor = width/w_i;
			Width_Large = w_i;
			Width_Small = width;
		}
		InputSizeChecked = true;
	}


	// Downsample if the option was set
	selectWindow(image);
	if (DownSamplingFactor < 1.0) {
		print("    INFO: Downsampling by factor " + d2s(DownSamplingFactor,5));
		target_height = floor(h_i * DownSamplingFactor);
		target_width = floor(w_i * DownSamplingFactor);
		run("downsample ", "width=" + target_width + " height=" + target_height + " source=0.50 target=0.50");	
	}
	
	if (DownSamplingFactor > 1.0) {
		print("    INFO: Downsampling by factor " + d2s(DownSamplingFactor,5));
		target_height = floor(2 * h_i * DownSamplingFactor);
		target_width = floor(2 * w_i * DownSamplingFactor);
		run("Scale...", "x="+DownSamplingFactor+" y="+DownSamplingFactor+" width="+target_height+" height="+target_width+" interpolation=Bilinear average create");
		upscaled_image = getTitle();
		close(image);
		selectWindow(upscaled_image);
		rename(image);
	}
	if (DownSamplingFactor == 1.0){
		print("    INFO: DownSampling not necessary");
	}

	// Now, get the correct image and split into Mask Slice and Data Slice
	selectWindow(image);
	run("Duplicate...", "title=MovingMask duplicate channels=" + MaskSlice + "-" + MaskSlice);
	wait(200);
	selectWindow(image);
	run("Duplicate...", "title=MovingData duplicate channels=" + DataSlice + "-" + DataSlice);
	wait(200);
	selectWindow(image);
	close();
	

	// return updated flags fr next iterations
	return newArray(InputFormatChecked, InputSizeChecked, DownSamplingFactor);
}

function TopBottomLayer (VolumeImage) {
	// Find boundaries of masked volumetric image along the z-direction	
	flag = false;
	first = 0;
	last = 0;
	selectWindow(VolumeImage);

	run("Set Measurements...", "area_fraction display redirect=None decimal=2");

	// iterate over all slices
	for (i = 1; i <= nSlices; i++) {
		setSlice(i);
		run("Measure");
		af = getResult("%Area", nResults - 1);

		// if white pixels are found: raise flag and memorize slice
		if ((flag == false) && (af > 0.0)) {
			flag = true;
			first = i;
		}

		// if flag is up (we're inside the mask) and af value drops to zero:
		if ((flag == true) && (af == 0.0)) {
			last = i-1;
			break;
		}		
	}
	vals = newArray(first, last);
	return vals;
}

function getImages(directory, subdir_string, ID){
	/*
	 * This function browses the supplied <directory>  in order to find all
	 * images that are designated as input from the 2D domain. 
	 * The images can be located in subdirectories directory/.../<subdir_path>/image.tif
	 * and/or have to match a given ID string <ID_string>
	 * 
	 * Returns: List of pathnames
	 */

	// First, examine file structure
	final_list = newArray();
	prelimary_list = newArray();
	prelimary_list2 = newArray();
	if (subdir_string == "") {
		
		// check subdir param. Take all files in <directory> as input if <subdir> is not set.
		prelimary_list = getFileListMod(directory, "file", true);
	
	} else {

		// ensure propper formatting for subdir string
		if (!endsWith(subdir_string, "/") && ! endsWith(subdir_string, "\\")) {
			subdir_string = subdir_string + "\\"; 
		}

		// else, get subdirs
		subdirlist = getFileListMod(directory, "dir", true);
		for (i = 0; i < subdirlist.length; i++) {

			path = subdirlist[i] + subdir_string;
			// check if specified structure exists and add files in subdir if existant
			if (!File.exists(path)) {
				continue;
			} else {
				
				// add files in subdir to list iteratively with full path
				a = getFileListMod(path, "file", false);
				for (j = 0; j < a.length; j++) {
					prelimary_list = Array.concat(prelimary_list, path + a[j]);
				}
			}
		}
	}

	// Only tif allowed!
	for (i = 0; i < prelimary_list.length; i++) {
		if (endsWith(prelimary_list[i], "tif")) {
			prelimary_list2 = Array.concat(prelimary_list2, prelimary_list[i]);
		}
	}
	
	// Second, sort found files
	for (i = 0; i < prelimary_list.length; i++) {
		name = File.getNameWithoutExtension(prelimary_list[i]);

		// check if filename - matching should be done
		if (ID == "") {
			final_list = Array.concat(final_list, prelimary_list[i]);
		} else {
			if (matches(name, ".*" + ID + ".*")) {
				final_list = Array.concat(final_list, prelimary_list[i]);
			}
		}
	}

	return final_list;	 
}

function LoadAndSegmentAtlas(filename, excl_labels, n_smooth){
	/*
	 * Open and Process a volume image - Won't do anything in the case of binary input (0,255)
	 */

	// 1. parse format string. This is to identify numbers (e.g. atlas regions) that should be removed from the volume.
	excl_labels = split(excl_labels, ",");
	labels = newArray(0);
	for (i = 0; i < excl_labels.length; i++) {

		// if a range of labels is given
		if (matches(excl_labels[i], ".*-.*")) {
			substr = split(excl_labels[i], "-");

			// convert label range to numbers and sort
			for (j = 0; j < substr.length; j++) {
				substr[j] = parseInt(substr[j]);
			}
			substr = Array.sort(substr);

			// Now add all numbers in specified range to list of labels
			for (j = parseInt(substr[0]); j <= parseInt(substr[1]); j++) {
				labels = Array.concat(labels, j);
			}
		// if single number is given
		} else {
			labels = Array.concat(labels, parseInt(excl_labels[i]));
		}
	}

	// 2. now remove undesired labels from atlas
	open(filename);
	TrgVolume = File.nameWithoutExtension;
	rename(TrgVolume);

	for (i = 1; i <= nSlices; i++) {
		setSlice(i);
		for (j = 0; j < labels.length; j++) {
			setThreshold(labels[j], labels[j]);
			run("Create Selection");
			if (selectionType == -1) {
				continue;
			}
			run("Clear", "slice");
		}
	}

	// 3. make Volume binary
	selectWindow(TrgVolume);
	setThreshold(1, 1e30);
	run("Convert to Mask", "stack");

	// Lastly, smooth outline if desired
	DilateErode(n_smooth);
	
	if(is("Inverting LUT")){
		run("Invert LUT");
	}
	
	return TrgVolume;
}

function DilateErode(n){
	// does an erosion-dilation smoothing with <n> iterations on the currently selected image

	run("Set Measurements...", "mean area_fraction display redirect=None decimal=2");
	for (i = 1; i <= nSlices; i++) {

		// Mask selected slice
		setSlice(i);

		// Check whether there is something to mask
		run("Measure");
		af = getResult("Mean", nResults - 1);
		if (af == 0) {
			continue;
		}
		
		setThreshold(128, 255);
		run("Create Selection");
		
		if (n <0) {
			// if n<0: Erode first, dilate later
			run("Enlarge...", "enlarge=-" + abs(n) + " pixel");
			run("Enlarge...", "enlarge=" + abs(n) + " pixel");
			
		} else {
			
			run("Enlarge...", "enlarge=" + abs(n) + " pixel");
			run("Enlarge...", "enlarge=-" + abs(n) + " pixel");
		}
		run("Set...", "value=255 slice");
	}

	// Remove threshold definition
	resetThreshold();
	run("Select None");
}

function getFileListMod (directory, type, fullpath){
	// Lists only the files or subdirs in a directory
	list = newArray();
	flist = getFileList(directory);
	for (i = 0; i < flist.length; i++) {
		if ((type == "dir") && File.isDirectory(directory + flist[i])) {

			if (fullpath) {
				list = Array.concat(list, directory + flist[i]);	
			} else {
				list = Array.concat(list, flist[i]);	
			}
		}

		if ((type == "file") && !File.isDirectory(directory + flist[i])) {
			if (fullpath) {
				list = Array.concat(list, directory + flist[i]);	
			} else {
				list = Array.concat(list, flist[i]);	
			}
		}
	}

	return list;
}

function createDirectories(input_dir, filename_Volume){
	// Create output directories for trafo file and result
	getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
	outdir = File.getParent(input_dir) + "\\" + 
			d2s(year,0) + d2s(month,0) + d2s(dayOfMonth, 0) + "_" + 
			d2s(hour,0) + d2s(minute,0) + d2s(second, 0) + 
			"_ResultOf_" + File.getName(input_dir) + "_to_" + File.getNameWithoutExtension(filename_Volume) + "\\";
	dir_trafo = outdir + "trafo\\";
	dir_res = outdir + "results\\";
	File.makeDirectory(outdir);
	File.makeDirectory(dir_trafo);
	File.makeDirectory(dir_res);
	return outdir;
}

function makeOverviewTable(){
	// Creates a table to keep overview about which image was assigned to which slice.

	if (isOpen(OverviewTable)) {
		close(OverviewTable);
	}
	
	OverviewTable = "[" + OverviewTable + "]";
	run("New... ", "name="+OverviewTable+" type=Table width=1000 height=200");

	print(OverviewTable, "\\Headings:Number\tFile\tDepth\tAssigned slice");
	setLocation(0, 0);
}

main();
print("Macro finished, have a nice day!");