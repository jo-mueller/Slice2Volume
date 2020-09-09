//script to registrate the dapi images on the ct image
//output is the Damage_Stack_int which includes all registered and interpolated dapi images



//clean up
close("*");
if (isOpen("Progress")) {
	close("Progress");
}

#@ String (visibility=MESSAGE, value="Elastix parameters", required=false) a
#@ File (label="Elastix parameter file", style="file") elastix_parameters
#@ File (label="Elastix installation directory", style="directory") elastix_dir

#@ String (visibility=MESSAGE, value="Input data", required=false) b
#@ File (label="Microscopy input", style="directory") dir_gH2AX
#@ File (label="Target Volume input", style="file") TrgVolume

#@ Integer (label="Mask channel", value=3) channel_mask
#@ Integer (label="Data channel", value=5) channel_data

#@ String (visibility=MESSAGE, value="Matching parameters", required=false) c
#@ Integer (label="Distance between subsequent sections (microns)") d_slice
#@ Integer (label="Target volume voxel size (microns)") d_CT
#@ Integer (label="Discarded tissue (microns)") shift
#@ Integer (label="Histo Outline smoothing degree", value=1) n_smoothing_hist
#@ Integer (label="Volume outline smoothing degree", value=3) n_smoothing_vol
#@ String (label="Exclude labels from Atlas", value = "102, 337-350") exclude_labels
#@ boolean  (label = "Batch mode", value=true) use_batch

setBatchMode(use_batch);


// Create output directories for trafo file and result
getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
outdir = File.getParent(dir_gH2AX) + "\\" + 
		d2s(year,0) + d2s(month,0) + d2s(dayOfMonth, 0) + "_" + 
		d2s(hour,0) + d2s(minute,0) + d2s(second, 0) + 
		"_ResultOf_" + topdir(dir_gH2AX) + "_2_" + "Volume" + "\\";
dir_trafo = outdir + "trafo\\";
dir_res = outdir + "results\\";


File.makeDirectory(outdir);
File.makeDirectory(dir_trafo);
File.makeDirectory(dir_res);

function LoadAndSegmentAtlas(filename, exclude_labels){
	/*
	 * Open and Segment an Atlas image according to a given format string 
	 */

	// parse format string
	exclude_labels = split(exclude_labels, ",");
	labels = newArray(0);
	for (i = 0; i < exclude_labels.length; i++) {

		// if a range of labels is given
		if (matches(exclude_labels[i], ".*-.*")) {
			substr = split(exclude_labels[i], "-");
			for (j = parseInt(substr[0]); j <= parseInt(substr[1]); j++) {
				labels = Array.concat(labels, j);
			}
		// if single number is given
		} else {
			labels = Array.concat(labels, parseInt(exclude_labels[i]));
		}
	}

	// now remove undesried labels from atlas
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

	// Lastly: make atlas binary
	selectWindow(TrgVolume);
	setThreshold(1, 1e30);
	run("Convert to Mask", "stack");

	return TrgVolume;
}

function topdir(path){
	// returns exclusively the top directory from full path
	path = split(path, "\\");
	return path[path.length-1];
}

function mapfilelist(){
	//returns an array with all map.tif files in the gH2AX folder
	
	maplist = newArray(0);									//create new array
	for (i = 0; i < lengthOf(Filelist); i++) {				//loop over all files in gH2AX folder
		if(!endsWith(Filelist[i], "map.tif")){				//take only map.tif files
			continue;
			}
		
		maplist2 = Array.concat(maplist, Filelist[i]);		//append new files
		maplist = maplist2;
			
		}
	return maplist;											//return the array
	}

	
function parseName(string){
	//returns number of dapi file where it is placed in the brain=slice location

	//get the highest slice number of the whole dapistack (=first file)
	maplist = mapfilelist();
	indexscene = indexOf(maplist[0], "Scene");									//Returns the index within first element of filelist of the first occurrence of "scene"
	top_slice_dapi = substring(maplist[0], indexscene - 5, indexscene - 1);		//pick string including the number
	top_slice_dapi = parseInt(top_slice_dapi);									//Converts string to an integer
	
	indexscene = indexOf(string, "Scene"); 						//Returns the index within current element of the first occurrence of "scene"
	//get the scene number of the file
	scene = substring(string, indexscene + 6, indexscene + 7);	//pick string including the scene number
	scene = parseInt(scene);									//Converts string to an integer
	//get the slice number of the file
	slice = substring(string, indexscene - 5, indexscene - 1);	//pick string including the slice number
	slice = parseInt(slice);									//Converts string to an integer

	number = (slice - top_slice_dapi) * 2 + scene; 				//get index of slice from top = 1,2,3,...
	dist_from_top = floor((number * d_slice + shift) / d_CT + 0.5);   //index of according CT slice noting the different slice distances

	return dist_from_top;										//returns slice location number
	}


function reslice(mask){
	//this function reslices all coronal brain-mask-slices (acquired from MITK software) 
	//into axial brain-mask-slices (from top to bottom)

	//open the file
	open(mask);

	// check if the image is actually binary.
	if(!is("binary")){
		print("WARNING: Input input is not a binary image. Attempting auto-conversion...");
		bd = bitDepth();
		setThreshold(1, 2^bd, "dark");
		run("Convert to Mask", "stack");

		// assure propper display
		if (is("Inverting LUT")) {
			run("Invert LUT");
		}
	}
	
	//reslice coronal into axial (output=sclice distance in microns, start with top slice)
	run("Reslice [/]...", "output=100 start=Top avoid interpolation");
	
	//close the coronal mask
	name = split(mask, "\\");			//split the root
	name = name[name.length - 1];		//pick the file name of the root
	close(name);						//close the mask
	}


function StackMaskin(path, deg_smoothing){
	//this function browses a list of ratio maps of the brain and 
	//extracts a external contour (=masks) for each slice
	
	// append // to path if not present
	if (!endsWith(path, "\\")) {
		path = path + "\\";
	}
	
	//Returns an array containing the names of the files in the folder.
	Filelist = getFileList(path);
	
	//loop over all images
	for (i = 0; i < lengthOf(Filelist); i++) {			
		//pick only the files which end with map.tif
		if(!endsWith(Filelist[i], "map.tif")){
		continue;
		}
		
		// Open maps
		open(path + Filelist[i]);
		name = File.nameWithoutExtension;				//name with extension removed.
		index = indexOf(name, "_map"); 					//Returns the index within current element of the first occurrence of "_map"
		mask = substring(name, 0, index) + "_DAPImask";	//define mask variable
		rename(name);									//Changes the title of the active image
	
		//Copy DAPI map
		setSlice(4);				//Displays the 4th slice of the active stack.
		run("Duplicate...", " ");	//Creates a new window containing a copy of the active image
		rename(mask);				//rename duplicated image
		close(name);				//close original image
	
		//Create Mask from DAPI image
		selectWindow(mask);			//Activates the window with the title "mask"
		setThreshold(4, 1e30);		//Sets the lower and upper threshold levels of image 
		run("Convert to Mask");		//Converts an image to black and white.
	
		//Postprocess
		run("Fill Holes");			//fills holes in objects by filling the background
		
		//Adds/removes pixels to the edges of objects in a binary image->makes image smoother
		for (j = 0; j < deg_smoothing; j++) {
			run("Erode");
			run("Erode");
		}
		for (j = 0; j < deg_smoothing; j++) {
			run("Dilate");
			run("Dilate");
		}
		
		run("Fill Holes");					//fill holes
		run("Rotate 90 Degrees Left");		//rotates image by 90 degrees
		saveAs(".tiff", path + mask);		//saves mask
		close("*");							//close all open images
		}
	}


function top_layer(mask){
	//returns the number of the top slice of a stack which is not black
	
	//array of the sum of all pixel values of one image for the whole stack 
	sumpixval = newArray(nSlices);		//create array with length = nSlices
	
	//fill the array-loop over all slices
	for (i = 1; i < nSlices + 1;) {			
			
		setSlice(i);																//set slice i
		run("Set Measurements...", "integrated density redirect=None decimal=2");	//set measurements
		run("Measure");																//run measure
		sumpixval[i - 1] = getResult("RawIntDen", nResults - 1);					//sum of all pixelvalues for current image
		i = i + 1; 																	//increase i by one
		}
	
	//get the top_slice by looking at nonzero elements of the array
	for (i = 1; i < nSlices + 1;) {		//loop over the entries of the array

		if(i == nSlices){															//error handling: if all images are black -> send error message
			 print("All of Your input images (CT or Dapi) contain no information/are completely black.");
			 selectWindow("Log");													
			 setLocation(0, 300); 
			}
		if(sumpixval[i] == 0){			//go to next entry if value is zero
			i = i + 1;	
			}
		else {							//get slice number if value is nonzero 
				
			top_slice = i + 1;	
			break;
			}
		}

	print("First non-zero volume slice = " + d2s(top_slice, 0));
	run("Clear Results");
	return top_slice;			//return value
	}


function bottom_layer(mask){
	//returns the number of the bottom slice of a stack which is not black
	
	//array of the sum of all pixel values of one image for the whole stack 
	sumpixval = newArray(nSlices);		//create array with length = nSlices
	
	//fill the array-loop over all slices
	for (i = 1; i < nSlices + 1;) {			
			
		setSlice(i);																//set slice i
		run("Set Measurements...", "integrated density redirect=None decimal=2");	//set measurements
		run("Measure");																//run measure
		sumpixval[i - 1] = getResult("RawIntDen", nResults - 1);					//sum of all pixelvalues for current image
		i = i + 1; 																	//increase i by one
		}
	
	//get the bottom_slice by first reversing the array and then looking at nonzero elements of the array
	sumpixval = Array.reverse(sumpixval)		//reverse array
	for (i = 1; i < nSlices + 1;) {				//loop over the entries of the array
	
		if(sumpixval[i] == 0){					//go to next entry if value is zero
				i = i + 1;	
			}
		else {									//get slice number if value is nonzero 
				
			bottom_slice = nSlices - i;	
			break;
			}
		}
	return bottom_slice;				//return value
	}


function progress(k) {
	//function which updates the progress bar
	
	print(title, "\\Update:" + k + "/" + 100 + " (" + k + "%)\n" + getBar(k, 100));		//Update the progress bar
	}


function getBar(p1, p2) {
	//function which creates the progress bar
	
    N = 20;		//number of progress bar intervals
    bar1 = "--------------------";
    bar2 = "********************";
    index = round(N * (p1 / p2));		//calculation when a progress asterisk (*) should be drawn
    if (index < 1) index = 1;
    if (index > N - 1) index = N - 1;
    return substring(bar2, 0, index) + substring(bar1, index + 1, N);	//return the bar
	}

function extractMask(image, s, savepath, n_smoothing){
	// Creates a mask of channel <s> in image <image>

	mask = image + "_mask"; 			// name of the generated mask
	selectWindow(image);				// select input stack
	setSlice(s); 						//Displays the desired slice of the active stack.
	run("Duplicate...", "title="+mask);	//Creates a new window containing a copy of the active image

	//Create Mask from DAPI image
	selectWindow(mask);			//Activates the window with the title "mask"
	setThreshold(4, 1e30);		//Sets the lower and upper threshold levels of image 
	run("Convert to Mask");		//Converts an image to black and white.

	//Postprocess
	run("Fill Holes");			//fills holes in objects by filling the background
	
	//Adds/removes pixels to the edges of objects in a binary image->makes image smoother
	for (j = 0; j < n_smoothing; j++) {
		run("Erode");
	}
	for (j = 0; j < n_smoothing; j++) {
		run("Dilate");
	}
	
	return mask;
}

function CoM_alignment(image, target){
	/*
	* embeds an input image <image> in a new image into a new blank image of width 
	* <width> and height <height> at position <x>, <y>
	*/

	output = image + "_embedded";
	
	selectWindow(image);
	type = bitDepth();
	w = getWidth();
	h = getHeight();
	run("Copy");

	selectWindow(target);
	run("Measure");
	XM = getResult("XM", nResults - 1); 	// Returns a measurement from the results table of the current measurment
	YM = getResult("YM", nResults - 1); 	// XM, YM are coordinates of center of mass
	_w = getWidth();
	_h = getHeight();
	newImage(output, d2s(type,0) + "-bit", _w, _h, 1); 	// Opens a new image with dimensions of 3D image
	run("Set...", "value=0");					// set all pixel values to 0 (=black image)
	
	//Emmbed dapimask in larger image (with dimensions of the ctmask image) to place unregistered dapimask slice image in center of mass of ctmask	
	//Creates a rectangular selection, where x and y are the coordinates (in pixels) of the upper left corner of the selection
	close(image);
	selectWindow(output);
	makeRectangle( 	round(XM - w/2), 
					round(YM - h/2), 
					w, h);
	run("Paste");
	
	return output;
}

function main(){
	//main function which includes three parts: registration via elastix, transformation and interpolation
	
	// Variables (TODO: are these really necessary?)
	Output_Stack = "Output_Stack";
	Output_Stack_int = "Interpolated_Output_Stack";
	Mask_3D = "Mask_3D";
	Data_2D = "Data_2D";


	//run "gH2AX_StackMaskin.ijm" script which creates the dapi image masks in the "gH2AX" folder
	//StackMaskin(dir_gH2AX, n_smoothing);
	
	//Returns an array containing the names of the files, here all gH2AX files (contains all dapimasks)
	Filelist = getFileList(dir_gH2AX);
	
	//Open Volume
	VolMask = LoadAndSegmentAtlas(TrgVolume, exclude_labels);
	run("Set Scale...", "distance=0");  //Use this dialog to define the spatial scale of the active image so measurement results can be presented in calibrated units, such as mm or μm. 
	
	w = getWidth();		//Returns the width in pixels of ct mask
	h = getHeight();    //Returns the height in pixels of ct mask
	n = nSlices;		//Returns the number of images in the current stack.
	
	//get number of the top slice of CT mask where one can actually see something with the "top_slice" script
	mask_top = top_layer(VolMask);
	
	//Create empty image for histo data storage (the damage stack will consist of the registered dapi images)
	newImage(Output_Stack, "32-bit", w, h, n);   //Opens a new stack using the name with certain properties
	run("Set...", "value=0");					 //set all pixel values to 0 (=black image)
	
	//set what you want to measure if you run(measure)
	run("Set Measurements...", "area center area_fraction display redirect=None decimal=2");

	//create a progress bar during the processing
	title = "[Progress]";														// title of the progress window
	run("Text Window...", "name="+ title +" width=50 height=5 monospaced");		// create a window for the progress bar
	selectWindow("Progress");													// select window
	setLocation(0, 0); 															// set location of the window
	maplist = mapfilelist();													// get maplist from function mapfilelist
	iteration = 100 /maplist.length;											// calculate the iteration steps of the progress
	k = 0;																		// set counter k to zero
	
	
	//Registration with "elastix" - one transformation file for every Mask slice - histo mask pair a transformation file 
	for (i = 0; i < lengthOf(Filelist); i++) {		//loop over all histo masks

		//Process Histo mask
		if(!endsWith(Filelist[i], "map.tif")){
			continue;
		}
		
			
		//Open histological input mask
		open(dir_gH2AX + "\\" + Filelist[i]);			//open ith histo file
		histo_input = File.nameWithoutExtension;		//without .tif
		rename(histo_input);							//rename to DAPImask
		run("Rotate 90 Degrees Left");					//rotates image by 90 degrees

		// extract mask image
		Mask_2D = extractMask(histo_input, channel_mask, dir_trafo, n_smoothing_hist); 	// mask the histological input

		//Parse filename and determine correct slice in 3D input
		dist_from_top = parseName(Filelist[i]);  		// get corresponding volume slice location from filename of DAPImask
		selectWindow(VolMask);							// select the window with the name "Ct_mask"
		setSlice(mask_top + dist_from_top);				// set certain slice number mask_top + dist_from_top in the Ct_mask stack
		run("Duplicate...", "title="+Mask_3D);			// duplicate the current image
		run("8-bit"); 									// smooth outline
		for (k = 0; k < n_smoothing_vol; k++) {
			run("Erode");
		}
		for (k = 0; k < n_smoothing_vol; k++) {
			run("Dilate");
		}


		Mask_2D = CoM_alignment(Mask_2D, Mask_3D);	// Center of Mass alignment of Mask 2D and Mask 3D

		//settings for elastix (registration program)
		FixedImage = dir_trafo + Mask_3D + "_" + i;		// Volume mask = target image 
		MovingImage = dir_trafo + Mask_2D + "_" + i;	// Histo mask = moving image which gets registered based on the target image

		// Save both masks and make sure they're nicely displayed
		selectWindow(Mask_2D);
		//getLocationAndSize(x, y, width, height);
		//setLocation(screenWidth/2 - width, 0);
		saveAs("tiff", MovingImage);	//save; that is the correct masked slice for the ith histomask
		close();

		selectWindow(Mask_3D);
		//setLocation(screenWidth/2, 0);
		saveAs("tiff", FixedImage);	//save; that is the correct masked slice of volume mask
		rename(Mask_3D);
	
		//execute elastix
		exec(elastix_dir + "\\elastix.exe",						//elastix installation directory
		"-f", FixedImage + ".tif", 								//set fixed image
		"-m", MovingImage + ".tif", 							//set moving image
		"-out", dir_trafo, 										//set output directory
		"-p", elastix_parameters);								//directory of elastix parameters used for the transformation		

		//get the name of the current 2Dmask file to set the name of the trafo file
		indexhisto = indexOf(Filelist[i], "map");					//Returns the index within first element of filelist of the first occurrence of "scene"
		Nametrafo = substring(Filelist[i], 0, indexhisto);			//pick string including the number
	
		//rename and delete unnecessary files
		File.rename(dir_trafo + "TransformParameters.0.txt", dir_trafo + Nametrafo + "trafo" + ".txt");	//rename trafo files
	    File.delete(dir_trafo + "IterationInfo.0.R0.txt");			//delete saved transformation process files
	    File.delete(dir_trafo + "IterationInfo.0.R1.txt");			//delete saved transformation process files
	    File.delete(dir_trafo + "IterationInfo.0.R2.txt");			//delete saved transformation process files
	    File.delete(dir_trafo + "elastix.log");						//delete Log
	    File.delete(FixedImage);									//delete saved fixed image
	    File.delete(MovingImage);									//delete saved moving image
	
		// Now run transformix based on determined transformation file.
		selectWindow(histo_input);
		setSlice(channel_data);
		run("Duplicate...", "title=Data_2D");	//duplicate the slice
		Data_2D = CoM_alignment("Data_2D", Mask_3D);

		MovingImage = dir_trafo + Data_2D + "_" + i;	// Histo mask = moving image which gets registered based on the target image
		trafo_file = Nametrafo + "trafo" + ".txt"; 		// set transformation file for right dapi image
		saveAs("tiff", MovingImage);
		rename(Data_2D);
		
		//execute transformix (transformation program-included in elastix)
		exec(elastix_dir + "\\transformix.exe",						// transformix installation directory
			"-in", MovingImage + ".tif",										// set moving image
			"-out", dir_res,										// set output directory
			"-tp", dir_trafo + trafo_file);							// set trafo file

		//Put transformed dapi images in damage Stack(=stack with all transformed dapi images)
		open(dir_res + "result.mhd");				//open transformed dapi image
		selectWindow("result.raw");
		run("Copy");								//copy dapi image
		selectWindow(Output_Stack);					//select the window "damage_stack"
		setSlice(mask_top + dist_from_top);			//set the right slice for this specific dapi image
		setMetadata("Label", Filelist[i]);			//Sets damage_ratio_map as the label of the current damage_stack slice
		run("Paste");								//copy dapi image in damage_stack

		close(Data_2D);
		close(Mask_2D);
		close(Mask_3D);
		close("result.raw");
		close(histo_input);

		progress(k);		//update the progress bar
		k += iteration;		//increase counter by one
	}	
	
	//interpolate missing slices
	//there are more ct slices than dapi slices -> interpolate every third dapi slice from the two adjacent slices
	selectWindow(Output_Stack);					//select the damage stack
	run("Duplicate...", "duplicate");			//duplicate the stack
	rename(Output_Stack_int);					//rename the duplicated stack, will be the interpolated stack
	
	//get top slice of of damage stack via "top_slice" function
	mask_top = top_layer(Output_Stack_int);				//convert to number
	
	//get bottom slice of damage stack via "bottom_slice" function
	mask_bottom = bottom_layer(Output_Stack_int);		//convert to number
	
	//set what you want to measure if you run(measure)
	run("Set Measurements...", "area center area_fraction display redirect=None decimal=2");
	
	//loop over all damage_stack_int slices
	for (i = 1; i < nSlices + 1; i++) {
		setSlice(i);			//set slice i
	
		//consider/interpolate only slices between bottom and top mask
		if (i <= mask_top){
			progress(k);		//update the progress bar
			k += iteration;		//increase counter by one
			continue;
			}
	
		if (i >= mask_bottom){
			progress(k);		//update the progress bar
			k += iteration;		//increase counter by one
			continue;
			}
	
		run("Measure");										//run measure of ith slice
		area_fraction = getResult("%Area", nResults - 1);	//measure the percentage of nonzero pixels in the image
	
		//interpolate all black images
		if (area_fraction == 0){			//pick all black images
			
			//copy slice i-1				
			setSlice(i - 1);				//set slice i-1
			run("Duplicate...", "slice");	//duplicate the slice
			rename("a");					//rename it to "a"
	
			//copy slice i+1
			selectWindow(Output_Stack_int);	//select the damage_stack_int
			setSlice(i + 1);				//set slice i+1
			run("Duplicate...", "slice");	//duplicate the slice
			rename("b");					//rename it to "b"
	
			//get average of a & b (=adjacent slices of the black image)
			imageCalculator("Average create 32-bit", "a","b");	//create the average
			rename("c");										//rename it to "c"
			close("a");											//close "a"
			close("b");											//close "b"
	
			//insert the interpolated slice into damage stack
			selectWindow("c");					//select the interpolated slice "c"
			run("Copy");						//copy the slice
			selectWindow(Output_Stack_int);		//select the damage_stack_int
			setSlice(i);						//set slice i
			run("Paste");						//paste the interpolated slice
	
			//Clean up
			close("c");     					//close the interpolated slice
			close(Output_Stack);				//close the damage_stack

			
			}

			progress(k);		//update the progress bar
			k += iteration;		//increase counter by one
		}
	//save the interpolated damage stack in root
	selectWindow(Output_Stack_int);
	saveAs(".tiff", root + "\\" + Output_Stack_int);
	
	//close unnecessary windows	
	selectWindow("Log");
    run("Close"); 
    selectWindow("Results");
    run("Close"); 
	wait(5000);
	selectWindow("Progress");
    run("Close"); 
	}

main();