//this script browses a list of ratio maps of the brain and extracts a external contour for each slice.

//clean up
close("*");


root = "D:\\Work\\Projects\\CT_SPR_MonteCarlo\\C3H_3\\gH2AX\\";
Filelist = getFileList(root);

for (i = 0; i < lengthOf(Filelist); i++) {

	if(endsWith(Filelist[i], "ratio.tif")){
		continue;
	}

	if(endsWith(Filelist[i], "_DAPImask.tif")){
		continue;
	}
	
	// Open maps
	open(root + Filelist[i]);
	name = File.nameWithoutExtension;
	mask = substring(name, 0, 32) + "_DAPImask"; 
	rename(name);

	// Copy DAPI map
	setSlice(4);
	run("Duplicate...", " ");
	rename(mask);
	close(name);

	// Create Mask from DAPI image
	selectWindow(mask);
	setThreshold(4, 1e30);
	run("Convert to Mask");

	// Postprocess
	run("Fill Holes");
	run("Dilate");
	run("Dilate");
	run("Dilate");
	run("Dilate");
	run("Erode");
	run("Erode");
	run("Erode");
	run("Erode");
	run("Fill Holes");
	run("Rotate 90 Degrees Left");

	saveAs(".tiff", root + mask);
	close("*");
}

