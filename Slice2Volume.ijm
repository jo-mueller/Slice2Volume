//clean up
close("*");
if (isOpen("Progress")) {
	
close("Progress");
}


#@ String (visibility=MESSAGE, value="Elastix parameters", required=false) a
#@ File (label="Elastix parameter file", style="file") elastix_parameters
#@ File (label="Elastix installation directory", style="directory") elastix_dir

#@ String (visibility=MESSAGE, value="Input data", required=false) b
#@ File (label="Microscopy input", style="directory") dir_2D
#@ File (label="Target Volume input", style="file") TrgVolume

#@ String (visibility=MESSAGE, value="File structure", required=false) d
#@ String (label="Subdirectory structure", value="") subdir_path
#@ String (label="Filename ID string", value="") ID_string

#@ String (visibility=MESSAGE, value="Geometric parameters", required=false) c
#@ Integer (label="Distance between subsequent sections (microns)") d_slice
#@ Integer (label="Target volume voxel size (microns)") d_Volume
#@ Integer (label="Discarded tissue (microns)") shift

#@ Integer (label="Histo Outline smoothing degree", value=1) n_smoothing_hist
#@ Integer (label="Volume outline smoothing degree", value=3) n_smoothing_vol
#@ String (label="Exclude values/labels from Volume", value = "102, 337-350") exclude_labels
#@ boolean  (label = "Batch mode", value=true) use_batch

// file path format
if (!endsWith(dir_2D, "/") && !endsWith(dir_2D, "\\")) {
	dir_2D = dir_2D + "\\";
}

main();

function main(){

	// Variables
	Output_Stack = "Output_Stack";
	var InputFormatChecked = false;		// flag for the dimensionality check of the 2D input data
	var InputSizeChecked = false;		// flag for the image size check of the 2D input data
	var MaskSlice = 1;					// Default value for 2D slice to be masked
	var DataSlice = 1;					// Default value for 2D slice to be transformed

	// Make directories
	outdir = createDirectories(dir_2D, TrgVolume);
	dir_trafo = outdir + "trafo\\";
	dir_res = outdir + "results\\";

	// First: Process the volumetric input and make corresponding output image
	Volume = LoadAndSegmentAtlas(TrgVolume, exclude_labels);
	newImage(Output_Stack, "8-bit black", getWidth(), getHeight(), nSlices);
	
	// Second: Determine boundaries of Volume image along the z-direction
	boundaries = TopBottomLayer(Volume);
	
	//Returns an array containing the names of the files from the 2D input
	ListOfImages = getImages(dir_2D, subdir_path, ID_string);

	// Iterate over all input files
	for (i = 0; i < ListOfImages.length; i++) {
		
	}

}

function Open2DImage(fname, volume) {
	// open 2D image from <fname> and do a couple of checks to provide a correct mask for registration.
	// For once, layers of the input image are checked and the size of the 2D plane is compared to the <volume> image

	// look at Volume
	selectWindow(volume);
	s = getWidth() * getHeight();
	
	image = open(fname);

	// first, check if images has mutiple layers. If so, user has to choose, which is maskable and which should be transformed
	if (nSlices > 1 && (InputFormatChecked == false)) {
		Dialog.create("User input required");
		Dialog.addMessage("The input image seems to have multiple layer.\nWhich of these is maskable (Mask slice) and which should be transformed (data slice)?");
		Dialog.addNumber("Mask slice", 1);
		Dialog.addNumber("Data slice", 1);
		Dialog.show();

		MaskSlice = Dialog.getNumber();
		DataSlice = Dialog.getNumber();
		InputFormatChecked = true;	// check this only once and keept setting throughout script.		
	}

	// second, check the image size dimension and offer downsampling CONTINUE HERE
	selectWindow(image);
	if () {
		
	}
	

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
					prelimary_list = Array.concat(prelimary_list, subdirlist[i] + a[j]);
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

function LoadAndSegmentAtlas(filename, excl_labels){
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

	return TrgVolume;
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
