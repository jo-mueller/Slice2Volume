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
#@ boolean  (label = "Batch mode", value=true) use_batch

// file path format
if (!endsWith(dir_2D, "/") && !endsWith(dir_2D, "\\")) {
	dir_2D = dir_2D + "\\";
}

// Global Variables
var InputFormatChecked = false;		// flag for the dimensionality check of the 2D input data
var InputSizeChecked = false;		// flag for the image size check of the 2D input data
var DownSamplingFactor = 1.0;
var MaskSlice = 1;					// Default value for 2D slice to be masked
var DataSlice = 1;					// Default value for 2D slice to be transformed

var OverviewTable = "OverviewTable"; 

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
	getDimensions(width, height, channels, slices, frames);
	setLocation(0, 200, width, height);
	newImage(Output_Stack, "8-bit black", getWidth(), getHeight(), nSlices);
	setLocation(width, 200, width, height);
	
	// Second: Determine boundaries of Volume image along the z-direction
	boundaries = TopBottomLayer(Volume);
	
	//Returns an array containing the names of the files from the 2D input
	ListOfImages = getImages(dir_2D, subdir_path, ID_string);

	// Iterate over all input files
	for (i = 0; i < ListOfImages.length; i++) {

		// open 2D image and split into mask and data
		Open2DImage(ListOfImages[i], Volume);
		MovingMask = "MovingMask";
		MovingData = "MovingData";

		// Make binary mask
		MovingMask = GenerateMask(MovingMask, n_smoothing_hist);

		// Find corresponding slice in Volume based on filename
		depth = findLocationInVol(	ListOfImages[i],	// currently processed image
									Volume,				// Target volume
									Output_Stack,		// Output stack
									boundaries,			// mask boundaries along z-direction
									shift,				// amount of discarded tissue in microns
									2,					// number of samples per carrier
									d_slice,			// slice distance of histological sections
									d_Volume);			// slice distance of volumetric image
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
		PasteToStack(TrnsfmdImg, Output_Stack);

		// Print to protocol
		print(OverviewTable, i+1+"\t"+ListOfImages[i]+"\t"+(depth - boundaries[0])*d_Volume + "microns\t"+depth);
		close(TargetMask + ".tif"); close(MovingData + ".tif"); close(MovingMask + ".tif");
	}

	// Post-process: Interpolate missing slices
	
}

//================================== FUNCTIONS =====================

function Interpolate_Stack(Vol, zBoundaries) {
	/*
	 * Makes copy of input volume <Vol> and interpolates black slices in the regions between
	 * <zBoundaries[0]> and <zBoundaries[1]>. 
	 */

	selectWindow(Vol);
	run("Duplicate...", "title=Interpolated_output_stack duplicate");
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
				selectWindow(Output_Stack_int);		//select the damage_stack_int
				setSlice(i + l);					//set slice i + l
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

function PasteToStack(image, V){
	/*
	 * Copies the contents of <image> and pastes them to the currently selected slice of Volume <V>
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

	print("    INFO: Moving image = " + MovImg);
	print("    INFO: Target image = " + TrgImg);
	TrgImg += ".tif";
	MovData += ".tif";
	MovImg += ".tif";
	
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

	// Third, clean up
	File.delete(MovData);
	File.delete(MovImg);
	File.delete(TrgImg);
	File.copy(wdir + "TransformParameters.0.txt", outdir + File.getNameWithoutExtension(filename) + "_trafo.txt");
	File.delete(wdir + "TransformParameters.0.txt");

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

	// Binarize
	selectWindow(MaskedImage);
	setAutoThreshold("Default dark");
	run("Convert to Mask");
	
	// Smooth
	DilateErode(N_Smooth);
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
	run("Rotate... ", "angle=" + init_rotation + " grid=1 interpolation=Bilinear stack");

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
	if (!InputSizeChecked && (w_i * h_i > 10* w * h)) {
		DoDownsampling = getBoolean("The input image ("+d2s(w_i, 0) "x" + d2s(h_i,0) +") is much larger than the target volume ("+d2s(w, 0) "x" + d2s(h,0) +").\n"+
									"Proceed with downsampled image?");
		// If desired, adjust settings for downsampling in all following images
		if (DoDownsampling) {
			DownSamplingFactor = w/w_i;
		}
		InputSizeChecked = true;
	}

	// Downsample if the option was set
	selectWindow(image);
	if (DownSamplingFactor < 1.0) {
		print("    INFO: Downsampling by factor " + d2s(DownSamplingFactor,3));
		run("downsample ", "width=" + floor(h * DownSamplingFactor) + " height=" + floor(h * DownSamplingFactor) + " source=0.50 target=0.50");	
	} else {
		print("    INFO: DownSampling not necessary");
	}

	// Now, get the correct image and split into Mask Slice and Data Slice	
	run("Duplicate...", "title=MovingMask duplicate channels=" + MaskSlice + "-" + MaskSlice);
	selectWindow(image);
	run("Duplicate...", "title=MovingData duplicate channels=" + DataSlice + "-" + DataSlice);
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
	
	return TrgVolume;
}

function DilateErode(n){
	// does an erosion-dilation smoothing with <n> iterations on the currently selected image

	if (n <0) {
		// if n<0: Erode first, dilate later
		for (i = 0; i < n; i++) {
			run("Erode", "stack");
		}
		for (i = 0; i < n; i++) {
			run("Dilate", "stack");
		}	
		
	} else {
		
		// if n>0: Dilate first, erode later
		for (i = 0; i < n; i++) {
			run("Dilate", "stack");
		}
		for (i = 0; i < n; i++) {
			run("Erode", "stack");
		}	
	}
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