/*
 * The trace script provides functionality to read slice assignment parameters
 * as determined by the Slice2Volume script. These parameters can then be used to
 * transform further stainings that align with the 2D input to Slice2Volume (such
 * as a different staining on the same sample or a co-registered tissue section) into the 
 * coordinate system of the target volume.
 * These other 2D input datasets must obey the same Filestructure as the original 
 * input 2D data
 * 
 * Author: Johannes Müller, johannes.mueller@ukdd.de
 * 
 * LICENSE
 */

// Clean up
 close("*");

 //================================== CONFIG =====================
#@ String (visibility=MESSAGE, value="Elastix parameters", required=false) a
#@ File (label="Elastix installation directory", style="directory") Elastix_dir
#@ File (label="Target Volume input", style="file") TrgVolume

#@ String (visibility=MESSAGE, value="Input data", required=false) b
#@ File (label="Silce2Volume result directory", style="directory") dir_S2V_res
#@ String (label="Filename ID string", value="") ID_string

#@ Boolean (label = "Batch mode?", value=true) use_batch

// Variables
var subdir_path = "";
var input_dir = "";
var DownSamplingFactor = 1.0;
var InitialRotation = 0.0;
var Symmetry_Correction_Angle = 0.0;
var Symmetry_Correction_Axis = "None";
var trafofiles = newArray();
var assignedSlices = newArray();

// file path format
if (!endsWith(dir_S2V_res, "/") && !endsWith(dir_S2V_res, "\\")) {
	dir_S2V_res = dir_S2V_res + "\\";
}



//================================== MAIN =====================

function main() {
	// Read Slice2Volume input
	getParams(dir_S2V_res);

	// find all images to be transformed
	images = getImages(input_dir, subdir_path, ID_string);

	// Make empty copy of target volume
	Volume = OpenVolume(TrgVolume);

	// transform images according to provided trafofiles
	for (i = 0; i < images.length; i++) {

		// Load
		slc = Load2Dimage(images[i]);

		// Transform
		trnsfd = transform(slc, trafofiles[i]);
		PasteToStack(trnsfd, Volume, assignedSlices[i]);
		close(trnsfd);
	}
}

//================================== FUNCTIONS =====================

function transform(image, trafofile){
	/*
	 * Input <image> is transformed with transformix.exe according to <trafofile>
	 */
	 
	// set working directory 
	wdir = File.getDirectory(File.getDirectory(trafofile)) + "/traces/";

	// create output dir
	if (!File.exists(wdir)) {
		File.makeDirectory(wdir);
	}
	
	saveAs("tif", wdir + image);

	if (!File.exists(trafofile) || !File.exists(Elastix_dir + "\\transformix.exe")) {
		print("Error: trafofile "+ trafofile + " or transformix at dir " + Elastix_dir + " not found!");
		exit();
	}
	
	// Call transformix
	exec(Elastix_dir + "\\transformix.exe",	//elastix installation directory
		"-in", wdir + image, 	//set moving image
		"-out", wdir, 	//set output directory
		"-tp", trafofile);	//directory of elastix parameters used for the transformation

	close(image + ".tif");
	open(wdir + "result.tif");

	return getTitle();

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

function OpenVolume(filename){
	/*
	 * Function to open target image and make a copy of it
	 * to store transformed images
	 */

	// input check
	if (!File.exists(filename)) {
		print("Error: Volume input doesn't exist: " + filename);
		exit();
	}

	// Open
	open(filename);
	vol = getTitle();
	getDimensions(width, height, channels, slices, frames);
	newImage("Output_" + ID_string, "32-bit black", width, height, slices);
	close(vol);

	return "Output_" + ID_string;
}

function Load2Dimage(filename){
	/*
	 * Loads specified image from filename and does downsampling, 
	 * if specified
	 */

	// check input
	if (!File.exists(filename)) {
		print("Couldnt find image " + filename);
		exit();
	}

	// open image
	open(filename);
	image = getTitle();

	// downsample
	w = getWidth();
	h = getHeight();

	run("downsample ", "width=" + floor(w * DownSamplingFactor) + " height=" + floor(h * DownSamplingFactor) + " source=0.50 target=0.50");
	run("Rotate... ", "angle="+InitialRotation+" grid=1 fill interpolation=None");

	return image;
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
			if (matches(name, ID) || matches(name, ID + "_r")){
				final_list = Array.concat(final_list, prelimary_list[i]);
			}
		}
	}
	return final_list;	 
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


function getParams (directory){
	/*
	 * This function reads all necessary parameters from the S2V results <directory>
	 */

	
	// Check existence
	logpath = directory + "results\\S2V_LogFile.txt";
	SliceAssignment_path = directory + "results\\SliceAssignment_Overview.txt";
	if (!File.exists(logpath)) {
		print("Error: S2V Logfile not found at adress: " + logpath);
		
	}
	if (!File.exists(SliceAssignment_path)) {
		print("Error: S2V Logfile not found at address: " + SliceAssignment_path);
	}

	// First: Logfile
	f = File.openAsString(logpath);
	rows = split(f, "\n");
	
	// iterate through lines
	for (i = 0; i < rows.length; i++) {

		// Data directory
		if (startsWith(rows[i], "Microscopy input")) {
			row = split(rows[i], "\t");
			input_dir = row[1];
		}
		
		// subdir string
		if (startsWith(rows[i], "Subdir")) {
			row = split(rows[i], "\t");
			subdir_path = row[1];
		}

		// get downsampling factor
		if (startsWith(rows[i], "Downsampling factor")) {
			row = split(rows[i], "\t");
			DownSamplingFactor = parseFloat(row[1]);	
		}
		
		// get initial rotation parameter
		if (startsWith(rows[i], "Initial rotation")) {
			row = split(rows[i], "\t");
			InitialRotation = parseInt(row[1]);	
		}
		
		// get correction angle parameter
		if (startsWith(rows[i], "Correction angle")) {
			row = split(rows[i], "\t");
			Symmetry_Correction_Angle = parseFloat(row[1]);
		}

		// get correction axis parameter
		if (startsWith(rows[i], "Correction axis")) {
			row = split(rows[i], "\t");
			Symmetry_Correction_Axis = row[1];
		}
	}

	// next: Slice assignment
	f = File.openAsString(SliceAssignment_path);
	rows = split(f, "\n");

	// iterate through lines, skip header
	for (i = 1; i < rows.length; i++) {
		row = split(rows[i], "\t");
		trafofiles = Array.concat(trafofiles, row[1]);
		assignedSlices = Array.concat(assignedSlices, row[3]);
	}

	// identify correct trafo files
	for (i = 0; i < trafofiles.length; i++) {
		ID = getID(trafofiles[i]);

		// determine correct trafo file
		trafofiles[i] = directory + "trafo/" + ID  + "_trafo.txt";
	}
}

function getID(filestring){
	// returns the essential ID string XXXX_Scene_YY from a given <filestring>
	filestring = replace(trafofiles[i], File.separator, "/");
	filestring = replace(filestring, ".txt", "_txt");
	filestring = replace(filestring, "-|/" , "_");
	
	// find ID in string
	filestring = split(filestring, "_");
	for (k = 0; k < filestring.length; k++) {
		if (filestring[k] == "Scene") {
			break;
		}
	}
	return filestring[k-1] + "_Scene_" + filestring[k+1];
}

main();