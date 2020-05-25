//script to registrate the dapi images on the ct image
//output is the Damage_Stack_int which includes all registered and interpolated dapi images

//////////////////////////////////INPUT PARAMETERS///////////////////////////////
<<<<<<< HEAD
root = "C:\\Users\\Acer\\Documents\\oncoray\\daten_theresa";
coronal_brain = "Brain.nrrd";
root2 = "C:\\test";
=======
root = "C:\\Users\\Acer\\Documents\\oncoray\\daten_theresa\\";
coronal_brain = "Brain.nrrd";
root2 = "C:\\test\\";
>>>>>>> origin/issue12
/////////////////////////////////////////////////////////////////////////////////



//clean up
close("*");	

// Variables
CT_mask = "CT_mask";
CT = "CT_coronal";
Damage_Stack = "Damage_Stack";
Damage_Stack_int = "Interpolated_Damage_Stack";
CT_slice_mask = "CT_slice_mask";

// settings
d_slice = 150.0; //histo slice distance (microns) between two dapi slices
d_CT    = 100.0; // CT slice distance (microns)
shift = 4; 		 //shifts the whole dapi stack x slices   

// File definitions 
dir_gH2AX = root + "\\gH2AX\\";
dir_trafo = root + "\\trafo\\";
elastix = root2 + "\\elastix-4.9.0-win64";


//run "gH2AX_StackMaskin.ijm" script which creates the dapi image masks in the "gH2AX" folder
StackMaskin(dir_gH2AX);

//Returns an array containing the names of the files, here all gH2AX files (contains all dapimasks)
Filelist = getFileList(dir_gH2AX);

// Open CT mask (with mitk produced) which is resliced in the axial plane due to the "call_reslice" script 
mitk_mask = root + "\\" + coronal_brain
//reslice = root + "call_reslice.ijm" 	
//runMacro(reslice, mitk_mask);
reslice(mitk_mask);
rename(CT_mask);
run("Set Scale...", "distance=0");  //Use this dialog to define the spatial scale of the active image so measurement results can be presented in calibrated units, such as mm or μm. 

w = getWidth();		//Returns the width in pixels of ct mask
h = getHeight();    //Returns the height in pixels of ct mask
n = nSlices;		//Returns the number of images in the current stack.

//get number of the top slice of CT mask where one can actually see something with the "top_slice" script
mask_top = top_layer(CT_mask);

// Create empty image for histo data storage (the damage stack will consist of the registered dapi images)
newImage(Damage_Stack, "32-bit", w, h, n);   //Opens a new stack using the name with certain properties
run("Set...", "value=0");					 // set all pixel values to 0 (=black image)


// Arrays that store the information on how much the DAPImasks were translated before registration
// before the actual registration we try to manualy shift the dapimask in the center of mass of the ct mask to make 
// registration easier
X_displacement = newArray(0);	//Returns an empty array 
Y_displacement = newArray(0);

// set what you want to measure if you  run(measure)
run("Set Measurements...", "area center area_fraction display redirect=None decimal=2");


// create a progress bar during the processing
title = "[Progress]";														// title of the progress window
run("Text Window...", "name="+ title +" width=50 height=5 monospaced");		// create a window for the progress bar
selectWindow("Progress");													//
setLocation(0, 0); 															// set location of the window
iteration = 100 / (2 * lengthOf(Filelist) / 3 + n - 1)						// calculate the iteration steps of the progress
k = 0;																		// set counter k to zero




// Registration with "elastix" - one saves for every CT mask - DAPI mask pair a transformation file 
for (i = 0; i < lengthOf(Filelist); i++) {		// loop over all DAPI masks

	// Process Histo mask
	if(!endsWith(Filelist[i], "_DAPImask.tif")){
		continue;
	}
		
	// Open DAPI mask
	open(dir_gH2AX + Filelist[i]);				//open ith dapimask
	DAPImask = File.nameWithoutExtension;		//without .tif
	rename(DAPImask);							//rename to DAPImask
	
	// Parse filename (get slice location) and set correct slice in CT
	dist_from_top = parseName(DAPImask);		// get distance from top of the ct slice
	selectWindow(CT_mask);						//select the window with the name "Ct_mask"
	setSlice(mask_top + dist_from_top);			//set certain slice number mask_top + dist_from_top in the Ct_mask stack
	run("Duplicate...", " ");					//duplicate the current image
	rename(CT_slice_mask);        				//rename
	run("8-bit");								//change the image to a 8-bit image
	run("Multiply...", "value=2");				//multiply all pixelvalues by 2 (make it consistent with the dapimask values)
	saveAs("tiff", dir_trafo+CT_slice_mask+i);	//save; that is the correct ctmask to the ith dapimask
	
	// get masks center of mass of CT mask slice (xy-koordinaten; brightness-weighted average)
	run("Measure");						//do measurement of ctmask
	_XM = getResult("XM", nResults -1); //Returns a measurement from the results table of the current measurment
	_YM = getResult("YM", nResults -1); //_XM,_YM are coordinates of center of mass


	// get bounding box of DAPI mask image and embed in larger image to ease registration
	selectWindow(DAPImask);			//select dapimask
	mask_width  = getWidth();		//get width of dapimask
	mask_height = getHeight();		//get height of dapimask
	run("Copy");					//Copies the contents of the current image selection to the internal clipboard

	// Emmbed dapimask in larger image (with dimensions of the ctmask image) to place unregistered dapimask slice image in center of mass of ctmask
	newImage(DAPImask + "_embedded", "8-bit", w, h, 1); // Opens a new image with dimensions of the ctmask image
	run("Set...", "value=0");							// set all pixel values to 0 (=black image)
	//Creates a rectangular selection, where x and y are the coordinates (in pixels) of the upper left corner of the selection
	makeRectangle( 	round(_XM - mask_width/2), 
					round(_YM - mask_height/2), 
					mask_width, mask_height); 
					
	//store info about translation in x- and y-direction of dapimask				
	X_displacement = Array.concat(X_displacement, round(_XM - mask_width/2)); //Returns a new array created by joining two arrays or values
	Y_displacement = Array.concat(Y_displacement, round(_YM - mask_height/2));

	//inserts the dapimask in the rectangular selection of the embedded dapimask image
	run("Paste");		//Inserts the contents of the internal clipboard
	run("Select None"); //Choose any of the selection tools and click outside the selection

	// replace small mask with embedded one
	close(DAPImask);
	selectWindow(DAPImask + "_embedded");
	rename(DAPImask);
	saveAs("tiff", dir_trafo+DAPImask+i);
	run("Select None");

	//settings for elastix (registration program)
	FixedImage= dir_trafo+CT_slice_mask + i + ".tif";			//ctmask = target image 
	MovingImage=dir_trafo+DAPImask+i+".tif";					//dapimask = moving image which gets registered based on the target image
	Outdir=dir_trafo;											//transformation output file

	//execute elastix
	exec(elastix + "\\elastix.exe "+							//elastix installation directory
	"-f " +  FixedImage  + " "+									//set fixed image
	"-m " +  MovingImage + " "+									//set moving image
	"-out "+ Outdir      + " "+									//set output directory
	"-p " + root2 +"\\elastix_parameters.txt");					//directory of elastix parameters used for the transformation

	//rename and delete unnecessary files
	File.rename(dir_trafo+"TransformParameters.0.txt", dir_trafo +"trafo" + i + ".txt");	//rename trafo files
    File.delete(dir_trafo+"IterationInfo.0.R0.txt");			//delete saved transformation process files
    File.delete(dir_trafo+"IterationInfo.0.R1.txt");			//delete saved transformation process files
    File.delete(dir_trafo+"IterationInfo.0.R2.txt");			//delete saved transformation process files
    File.delete(FixedImage);									//delete saved fixed image
    File.delete(MovingImage);									//delete saved moving image

	close(CT_slice_mask + i+ ".tif");							//close ctmask
	close(DAPImask+i+".tif");									//close dapimask

	progress(k);		// update the progress bar
	k += iteration;		// increase counter by one
}




// Transformation (apply transformation files on the actual dapi images)
counter = 0;		//set counter (counts the entries of the displacement arrays)

//loop over all ration files (real dapi images)
for (i = 0; i < lengthOf(Filelist); i++) {

	if(!endsWith(Filelist[i], "_ratio.tif")){		//pick only ratio=dapi files
		continue;
	}
	
	// Open the ratio map
	open(dir_gH2AX + Filelist[i]);					//open the dapi file
	run("Rotate 90 Degrees Left");					//rotate the image 90 degrees
	damage_ratio_map = File.nameWithoutExtension;	//set variable (damage_ratio_map=ratio file)
	rename(damage_ratio_map);						//rename the ratio image with damage_ratio_map
	mask_width  = getWidth();						//get width of the ratio image
	mask_height = getHeight();						//get height of the ratio image
	run("Copy");									//copy the dapi image
	close(damage_ratio_map);						//close the dapi image

	// embed in larger image (put the smaller dapi image in the empty but bigger ct image format in a certain position)
	newImage(damage_ratio_map + "_embedded", "32-bit", w, h, 1);		//embedded image with ct image dimensions
	run("Set...", "value=0");											//set all pixel values to zero (=black image)
	//Creates a rectangular selection, where x and y are the coordinates (in pixels) of the upper left corner of the selection
	makeRectangle(	X_displacement[counter],
					Y_displacement[counter], 
					mask_width, mask_height);

	counter +=1;													// counter +1
	run("Paste");													// copy the dapi image in the bigger embedded image
	rename(damage_ratio_map);										//rename to damage_ratio_map
	saveAs("tiff", dir_trafo + damage_ratio_map + i + ".tif");		//save the edited dapi image
	run("Select None");												//Clears any selection from the active images 


	// Calculate according (to current dapi image) CT slice location
	dist_from_top = parseName(damage_ratio_map);
	
	//transform dapi image with received transformation file
	Outdir=dir_trafo;											//transformated dapi image output file
	MovingImage=dir_trafo + damage_ratio_map + i + ".tif";		//moving image=dapi image
	trafo_file = "trafo" + i+1 + ".txt"; 						//set transformation file for right dapi image
	
	//execute transformix (transformation program-included in elastix)
	exec(elastix + "\\transformix.exe "+						//transformix installation directory
	"-in " + MovingImage + " "+									//set moving image
	"-out "+ Outdir      + " "+									//set output directory
	"-tp " + dir_trafo+trafo_file);								//set trafo file

	
	// Put transformed dapi images in damage Stack(=stack with all transformed dapi images)
	open(dir_trafo + "result.mhd");				//open transformed dapi image
	run("Copy");								//copy dapi image
	selectWindow(Damage_Stack);					//select the window "damage_stack"
	setSlice(mask_top + dist_from_top);			//set the right slice for this specific dapi image
	setMetadata("Label", damage_ratio_map);		//Sets damage_ratio_map as the label of the current damage_stack slice
	run("Paste");								//copy dapi image in damage_stack

	close(damage_ratio_map + i + ".tif");		//close dapi images
	close("result.raw");						//close result.raw
	close(damage_ratio_map);					//close damage_ratio_map

	File.delete(dir_trafo+"result.raw");		//delete result file
    File.delete(MovingImage);					//delete moving image file

    indexscene = indexOf(Filelist[i], "Scene");								//Returns the index within first element of filelist of the first occurrence of "scene"
	Name = substring(Filelist[i], indexscene-5, indexscene+7);				//pick string including the number
    File.rename(dir_trafo +"trafo" + i-2 + ".txt", dir_trafo + "trafo_" + Name + ".txt");	//rename trafo files

	progress(k);		// update the progress bar
	k += iteration;		// increase counter by one    
	
}
close(CT_mask);		//close ctmask





//interpolate missing slices
//there are more ct slices than dapi slices -> interpolate every third dapi slice from the two adjacent slices
selectWindow(Damage_Stack);					//select the damage stack
run("Duplicate...", "duplicate");			//duplicate the stack
rename(Damage_Stack_int);					//rename the duplicated stack, will be the interpolated stack

//get top slice of of damage stack via "top_slice.ijm" script
mask_top = top_layer(Damage_Stack_int);		// convert to number

//get bottom slice of damage stack via "bottom_slice.ijm" script
mask_bottom = bottom_layer(Damage_Stack_int);				// convert to number

// set what you want to measure if you  run(measure)
run("Set Measurements...", "area center area_fraction display redirect=None decimal=2");



//loop over all damage_stack_int slices
for (i = 1; i < nSlices+1; i++) {
	setSlice(i);			//set slice i

	//consider/interpolate only slices between bottom and top mask
	if (i<=mask_top){
		progress(k);		// update the progress bar
		k += iteration;		// increase counter by one
		continue;
	}

	if (i>=mask_bottom){
		progress(k);		// update the progress bar
		k += iteration;		// increase counter by one
		continue;
	}

	run("Measure");										//run measure of ith slice
	area_fraction = getResult("%Area", nResults-1);		//measure the percentage of nonzero pixels in the image

	//interpolate all black images
	if (area_fraction == 0){			//pick all black images
		
		//copy slice i-1				
		setSlice(i-1);					//set slice i-1
		run("Duplicate...", "slice");	//duplicate the slice
		rename("a");					//rename it to "a"

		//copy slice i+1
		selectWindow(Damage_Stack_int);	//select the damage_stack_int
		setSlice(i+1);					//set slice i+1
		run("Duplicate...", "slice");	//duplicate the slice
		rename("b");					//rename it to "b"

		//get average of a & b (=adjacent slices of the black image)
		imageCalculator("Average create 32-bit", "a","b");	//create the average
		rename("c");										//rename it to "c"
		close("a");											//close "a"
		close("b");											//close "b"

		// insert the interpolated slice into damage stack
		selectWindow("c");					//select the interpolated slice "c"
		run("Copy");						//copy the slice
		selectWindow(Damage_Stack_int);		//select the damage_stack_int
		setSlice(i);						//set slice i
		run("Paste");						//paste the interpolated slice

		//Clean up
		close("c");     					//close the interpolated slice
		close("Damage_stack");				//close the damage_stack
	}
	progress(k);		// update the progress bar
	k += iteration;		// increase counter by one
}
//close unnecessary windows	
selectWindow("Log");
run("Close"); 
selectWindow("Results");
run("Close"); 
wait(5000);
selectWindow("Progress");
run("Close"); 



//returns number of dapi file where it is placed in the brain=slice location
function parseName(string){

	//get the highest slice number of the whole dapistack (=first file)
	indexscene = indexOf(Filelist[0], "Scene");								//Returns the index within first element of filelist of the first occurrence of "scene"
	top_slice_dapi = substring(Filelist[0], indexscene-5, indexscene-1);	//pick string including the number
	top_slice_dapi = parseInt(top_slice_dapi);								//Converts string to an integer
	
	indexscene = indexOf(string, "Scene"); 					//Returns the index within current element of the first occurrence of "scene"
	//get the scene number of the file
	scene = substring(string, indexscene+6, indexscene+7);	//pick string including the scene number
	scene = parseInt(scene);								//Converts string to an integer
	//get the slice number of the file
	slice = substring(string, indexscene-5, indexscene-1);	//pick string including the slice number
	slice = parseInt(slice);								//Converts string to an integer

	number = (slice-top_slice_dapi)*2 + scene; 				// get index of slice from top = 1,2,3,...
	dist_from_top = floor((number * d_slice)/d_CT) + shift; // index of according CT slice noting the different slice distances

	return dist_from_top;									//returns slice location number
}




function reslice(mask){
//this script reslices all coronal brain-mask-slices (acquired from MITK software) 
//into axial brain-mask-slices (from top to bottom)

//open the file
open(mask);

//reslice coronal into axial (output=sclice distance in microns, start with top slice)
run("Reslice [/]...", "output=100 start=Top avoid interpolation");

//close the coronal mask
name = split(mask, "\\");			//split the root
name = name[name.length-1];			//pick the file name of the root
close(name);						//close the mask
}




function StackMaskin(root){
//this script browses a list of ratio maps of the brain and 
//extracts a external contour (=masks) for each slice

//Returns an array containing the names of the files in the folder.
Filelist = getFileList(root);

//loop over all images
for (i = 0; i < lengthOf(Filelist); i++) {			
	//pick only the files which end with map.tif
	if(endsWith(Filelist[i], "ratio.tif")){			
		continue;
	}
	if(endsWith(Filelist[i], "_DAPImask.tif")){
		continue;
	}
	
	// Open maps
	open(root + Filelist[i]);
	name = File.nameWithoutExtension;				//name with extension removed.
	index = indexOf(name, "_map"); 					//Returns the index within current element of the first occurrence of "_map"
	mask = substring(name, 0, index) + "_DAPImask";	//define mask variable
	rename(name);									//Changes the title of the active image

	// Copy DAPI map
	setSlice(4);				//Displays the 4th slice of the active stack.
	run("Duplicate...", " ");	//Creates a new window containing a copy of the active image
	rename(mask);				//rename duplicated image
	close(name);				//close original image

	// Create Mask from DAPI image
	selectWindow(mask);			//Activates the window with the title "mask"
	setThreshold(4, 1e30);		//Sets the lower and upper threshold levels of image 
	run("Convert to Mask");		//Converts an image to black and white.

	// Postprocess
	run("Fill Holes");			//fills holes in objects by filling the background
	//Adds/removes pixels to the edges of objects in a binary image->makes image smoother
	run("Dilate");
	run("Dilate");
	run("Dilate");
	run("Dilate");
	run("Erode");
	run("Erode");
	run("Erode");
	run("Erode");
	
	run("Fill Holes");					//fill holes
	run("Rotate 90 Degrees Left");		//rotates image by 90 degrees
	saveAs(".tiff", root + mask);		//saves mask
	close("*");							//close all open images
	}
}




function top_layer(mask){
//returns the number of the top slice of a stack which is not black

//array of the sum of all pixel values of one image for the whole stack 
sumpixval = newArray(nSlices);		//create array with length = nSlices

//fill the array-loop over all slices
for (i = 1; i < nSlices+1;) {			
		
	setSlice(i);																//set slice i
	run("Set Measurements...", "integrated density redirect=None decimal=2");	//set measurements
	run("Measure");																//run measure
	sumpixval[i-1] = getResult("RawIntDen", nResults -1);						//sum of all pixelvalues for current image
	i=i+1; 																		//increase i by one
	}

//get the top_slice by looking at nonzero elements of the array
for (i = 1; i < nSlices+1;) {		//loop over the entries of the array

	if(sumpixval[i] == 0){			//go to next entry if value is zero
		i=i+1;	
		}
	else {							//get slice number if value is nonzero 
			
		top_slice = i+1;	
		break;
		}
}

return top_slice;			//return value
}




function bottom_layer(mask){
//returns the number of the bottom slice of a stack which is not black

//array of the sum of all pixel values of one image for the whole stack 
sumpixval = newArray(nSlices);		//create array with length = nSlices

//fill the array-loop over all slices
for (i = 1; i < nSlices+1;) {			
		
	setSlice(i);																//set slice i
	run("Set Measurements...", "integrated density redirect=None decimal=2");	//set measurements
	run("Measure");																//run measure
	sumpixval[i-1] = getResult("RawIntDen", nResults -1);						//sum of all pixelvalues for current image
	i=i+1; 																		//increase i by one
	}

//get the bottom_slice by first reversing the array and then looking at nonzero elements of the array
sumpixval = Array.reverse(sumpixval)		//reverse array
for (i = 1; i < nSlices+1;) {				//loop over the entries of the array

	if(sumpixval[i] == 0){					//go to next entry if value is zero
			i=i+1;	
		}
	else {									//get slice number if value is nonzero 
			
		bottom_slice = nSlices - i;	
		break;
		}
	}

return bottom_slice;				//return value
<<<<<<< HEAD
}
=======
}


function progress(k) {
	//function which updates the progress bar
	
	print(title, "\\Update:" + k + "/" + 100 + " (" + k + "%)\n" + getBar(k, 100));	// Update the progress bar
	}


function getBar(p1, p2) {
	// function which creates the progress  bar
	
    N = 20;		// number of progress bar intervals
    bar1 = "--------------------";
    bar2 = "********************";
    index = round(N * (p1 / p2));		// calculation when a progress asterisk (*) should be drawn
    if (index < 1) index = 1;
    if (index > N - 1) index = N - 1;
    return substring(bar2, 0, index) + substring(bar1, index + 1, N);	// return the bar
	}
>>>>>>> origin/issue12
