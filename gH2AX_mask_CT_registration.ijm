//clean up
//close("*");

// Variables
CT_mask = "CT_mask";
CT = "CT_coronal";
Damage_Stack = "Damage_Stack";
CT_slice_mask = "CT_slice_mask";
DoseMap = "DoseMap";
mask_top = 187; // highest slice of brain mask

// settings
d_slice = 150.0; //histo slice distance (microns)
d_CT    = 100.0; // CT slice distance (microns)

// File definitions
root = "D:\\Work\\Projects\\CT_SPR_MonteCarlo\\C3H_3\\";
dir_gH2AX = root + "gH2AX\\";
dir_trafo = root + "trafo\\"
dir_CT    = root + "CT\\";

Filelist = getFileList(root + "gH2AX\\");

// Open CT mask
open(root + "CT_brain_mask.tif");
rename(CT_mask);

// Create empty image for histo data storage
run("Duplicate...", "duplicate");
run("Select All");
setBackgroundColor(0, 0, 0);
run("Clear", "stack");
run("Select None");
rename(Damage_Stack);

/*
// Registration
for (i = 0; i < lengthOf(Filelist); i++) {

	// Process Histo mask
	if(!endsWith(Filelist[i], "_DAPImask.tif")){
		continue;
	}
		
	// Open DAPI mask
	open(dir_gH2AX + Filelist[i]);
	DAPImask = File.nameWithoutExtension;

	// Parse filename (get slice location)
	dist_from_top = parseName(DAPImask);

	// registration
	selectWindow(CT_mask);
	setSlice(mask_top + dist_from_top);
	
	run("Duplicate...", " ");
	rename(CT_slice_mask);

	print("Registering " + DAPImask + " with CT slice #" + d2s(mask_top + dist_from_top, 0));
	direct_trafo = dir_trafo + DAPImask + "_direct_transf.txt";
	inverse_trafo = dir_trafo + DAPImask + "_inverse_transf.txt";

	run( "bUnwarpJ", "source_image="+Filelist[i]+" target_image="+CT_slice_mask+" registration=Mono "
      + "image_subsample_factor=0 initial_deformation=[Coarse] "
      + "final_deformation=[Very Fine] divergence_weight=2.0 curl_weight=0.1 landmark_weight=0 "
      + "image_weight=1 consistency_weight=1 stop_threshold=0.01 "
      + "save_transformations "
      + "save_direct_transformation="+direct_trafo
      + " save_inverse_transformation="+ inverse_trafo);
	close("Registered Target Image");
	close("Registered Source Image");
	close(CT_slice_mask);
	close(DAPImask + ".tif");
}


// Transformation
for (i = 0; i < lengthOf(Filelist); i++) {

	if(!endsWith(Filelist[i], "_ratio.tif")){
		continue;
	}
	
	// Open the ratio map
	open(dir_gH2AX + Filelist[i]);
	run("Rotate 90 Degrees Left");
	damage_ratio_map = File.nameWithoutExtension;

	// Calculate according CT slice location
	dist_from_top = parseName(damage_ratio_map);

	// get name of transform file
	name = split(damage_ratio_map, "_");
	trafoname = name[0] + "_" + name[1] + "_" + name[2] + "_" + name[3] + "_" + name [4] + "_" + name[5] + "_DAPImask_direct_transf.txt";
	print(dir_trafo + trafoname);

	//Transform
	call("bunwarpj.bUnwarpJ_.loadElasticTransform", dir_trafo + trafoname, Damage_Stack, damage_ratio_map + ".tif");

	// Put in damage Stack
	run("Copy");
	selectWindow(Damage_Stack);
	setSlice(mask_top + dist_from_top);
	setMetadata("Label", damage_ratio_map);
	run("Paste");	

	close(damage_ratio_map + ".tif");

}

run("Fire");


//Load CT
run("Image Sequence...", "open="+dir_CT+"/CT_0000.dcm sort");
run("Reslice [/]...", "output=0.100 start=Top avoid");
run("32-bit");
rename(CT);

// Load doseMap
open(root + "DoseMap//DoseMap_full.tiff");
rename(DoseMap);
run("Rotate 90 Degrees Right");
run("Merge Channels...", "c1="+DoseMap+" c4="+CT+" create keep");
rename("MERGE");
*/

for (i = 1; i <= 351; i++) {
	selectWindow(Damage_Stack);
	setSlice(i);

	selectWindow("MERGE");
	setSlice(i);
	run("Add Image...", "image="+Damage_Stack+" x=0 y=0 opacity=50");
}



function parseName(string){
	// parsing slice location
	a = split(string, "_");
	a = split(a[4], "-");

	slice = parseInt(a[0]); // get slice
	scene = parseInt(a[2]); // get scene

	number = (slice-1)*2 + scene; // get index of slice from top
	dist_from_top = floor((number * d_slice)/d_CT); // index of according CT slice

	return dist_from_top
}
