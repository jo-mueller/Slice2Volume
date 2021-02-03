/*
 * This script reads all output as produced by the Slice2Volume macro and allows
 * to project the correct slice in a 3d-volume as it was used by S2V onto any given 
 * histological plane, provided the transformations of this plane have been
 * determined by Slice2Volume.
 * For more information, see https://github.com/jo-mueller/Slice2Volume
 */

close("*");

 //================================== CONFIG =====================
#@ String (visibility=MESSAGE, value="Necessary input parameters.", required=false) a
#@ File (label="Elastix installation directory", style="directory") elastix_dir

#@ File (label="Volumetric input", style="file") f_Vol
#@ File (label="Target tissue section", style="file") f_slice
#@ String (visibility=MESSAGE, value="The S2V output directory should contain the subdirectories \"results\" and \"trafo\".", required=false) _a
#@ File (label="S2V output directory", style="directory") dir_S2V

 //================================== Variables =====================

var cut_dist = 0;
var discarded_tissue = 0;
var vol_slice_dist = 0;
var init_rotation = 0;
var correction_angle = 0;
var correction_axis = "None";
var dir_out = "";

 //================================== MAIN =====================
function main(){

	// Make output directory
	if (!File.exists(dir_S2V + "/projected/")) {
		dir_out = dir_S2V + "/projected/";
		File.makeDirectory(dir_out);
	} else {
		dir_out = dir_S2V + "/projected/";
	}

	// Step 0: parse input
	parse_S2V(dir_S2V);
	coords = parse_section(f_slice);
	
	// 1st step: apply rotation along symmetry correction axis
	Volume = openVolume(f_Vol);
	InverseSymmetryCorrection(Volume);

	// 2nd step: find correct slice that corresponds to target slice
	slice = getSlice(Volume, coords);

	// 3rd step: trnsform with correct inverse trafo file
	trafofile = getTrafo(dir_S2V, coords);

	// 4th step: Do transform
	doTransform(elastix_dir, trafofile, slice, f_slice);
	
}

function doTransform(elastix_dir, trafo, moving_image, target_image){
	// apply transformation to input image nd scale to target image dimensions

	f_moving = dir_out + moving_image + ".tif";
	saveAs("tif", f_moving);
	
	exec(elastix_dir + "\\transformix.exe",	//elastix installation directory
		"-in", f_moving, 	//set moving image
		"-out", dir_out, 	//set output directory
		"-tp", trafo);	//directory of elastix parameters used for the transformation

	open(dir_out + "/result.tif");
	projected_img =  getTitle();

	open(target_image);
	target_img =  getTitle();

	// upscale
	getDimensions(width, height, channels, slices, frames);
	selectWindow(projected_img);
	//run("Scale...", "x=- y=- width="+width+" height=" + height + " interpolation=None average");
	
}

function getTrafo(dir, coordinates){
	// Identify the transformix transformation file that corresponds to the parset slice coordinates (XXXX_Scene_Y)
	expected_name = dir + "/trafo/" + IJ.pad(coordinates[0], 4) + "_Scene_" + d2s(coordinates[1], 0) + "_trafo_inverse.txt";

	if (!File.exists(expected_name)) {
		print("Error: " + expected_name + " doesnt exist.");
		exit();
	}
	return expected_name;
}

function getSlice(Vol, slice_coords){
	// Determine corresponding slice in volume image that belongs to histo-slice

	Vol_bounds = TopBottomLayer(Vol);
	print(discarded_tissue, vol_slice_dist, cut_dist);
	slc = Vol_bounds[0] + discarded_tissue/vol_slice_dist + cut_dist * (2*(slice_coords[0] - 1) + (slice_coords[1]-1))/vol_slice_dist;
	setSlice(floor(slc));

	run("Duplicate...", "title=slice_duplicate");
	slc = getTitle();
	close(Vol);

	return slc;

}

function InverseSymmetryCorrection(Vol){
	// Apply previously determined symmetry correction
	if (correction_axis == "None") {
		return Vol;
	}
	selectWindow(Vol);
	if (correction_axis == "Y") {
		run("Reslice [/]...", "output=0.100 start=Top avoid");
	}
	if (correction_axis == "X") {
		run("Reslice [/]...", "output=0.100 start=Left avoid");
	}
	resliced = getTitle();
	close(Vol);

	// apply correction angle
	selectWindow(resliced);
	run("Rotate... ", "angle=" + d2s(correction_angle, 1) +" grid=1 interpolation=None stack");
	
	if (correction_axis == "Y") {
		run("Reslice [/]...", "output=0.100 start=Top avoid");
	}
	if (correction_axis == "X") {
		run("Reslice [/]...", "output=0.100 start=Left avoid");
	}
	rename(Vol);
	close(resliced);
}

function openVolume(fname){
	open(fname);
	title = File.getNameWithoutExtension(fname);
	rename(title);
	return title; 
}

function parse_S2V(directory){
	// parsing all config data from S2V
	if (!File.exists(directory + "/results/")) {
		print("Error: S2V directory " + directory + "/results/ required but doesn't exist.")
		exit();
	}

	if (!File.exists(directory + "/trafo/")) {
		print("Error: S2V directory " + directory + "/trafo/ required but doesn't exist.")
		exit();
	}

	// parse logfile
	f = File.openAsString(directory + "/results/S2V_LogFile.txt");
	f = split(f, "\n");

	// go through lines of logfile
	for (i = 0; i < f.length; i++) {
		if (startsWith(f[i], "Cut distance")) {
			line = split(f[i], ":");
			cut_dist = parseFloat(line[1]);
		}
		
		if (startsWith(f[i], "Volume slice distance")) {
			line = split(f[i], ":");
			vol_slice_dist = parseFloat(line[1]);
		}

		if (startsWith(f[i], "Discarded tissue")) {
			line = split(f[i], ":");
			discarded_tissue = parseFloat(line[1]);
		}

		if (startsWith(f[i], "Initial rotation")) {
			line = split(f[i], ":");
			init_rotation = parseFloat(line[1]);
		}

		if (startsWith(f[i], "Correction angle")) {
			line = split(f[i], ":");
			correction_angle = parseFloat(line[1]);
		}

		if (startsWith(f[i], "Correction axis")) {
			line = split(f[i], "\t");
			correction_axis = substring(line[1], 0, 1);
		}
	}
}

function parse_section(fname){
	// parse name of target tissue section

	coordinates = newArray(2);
	
	filestring = replace(fname, File.separator, "/");
	filestring = replace(filestring, ".tif", "_tif");
	filestring = replace(filestring, "-|/" , "_");
	filestring = split(filestring, "_");
	
	for (i = 0; i < filestring.length; i++) {
		if (filestring[i] == "Scene") {
			coordinates[0] = parseInt(filestring[i - 1]);
			coordinates[1] = parseInt(filestring[i + 1]);
			break;
		}
	}
	return coordinates;	
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


main();