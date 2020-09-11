// Requires ImageJ 1.52u or later

//this command is needed to access the metadata via bio-formats
run("Bio-Formats Macro Extensions");
close("*");

//Input
#@ String (visibility=MESSAGE, value="Input data", required=false) a
#@ File (label= "10x image", style="file") filename_10x
#@ File (label= "40x image", style="file") filename_40x
#@ File (label= "Elastix transformation file", style="file") filename_trafo

#@ String (visibility=MESSAGE, value="Spot detection parameters", required=false) b
#@ Integer (label="Tesellation tile size", value=256) tilesize
#@ Integer (label="Tesellation downsample factor", value=2) series_SpotDet

#@ String (visibility=MESSAGE, value="Processing input (keep default values if you don't know what it does)", required=false) c
#@ Integer(label="Downsample factor 10x", value=5) series_10x
#@ Integer(label="Downsample factor 40x", value=5) series_40x



//open and extract info from 10x and 40x image
Img_10x = SeriesOpen(filename_10x, series_10x);
Img_40x = SeriesOpen(filename_40x, series_40x);

getPixelSize(unit, pixelWidth, pixelHeight);
TablePos_10x = getMotorCenter(filename_10x);
TableSize_10x = getMotorFrame(filename_10x);
TablePos_40x = getMotorCenter(filename_40x);
TableSize_40x = getMotorFrame(filename_40x);

Array.show(TableSize_10x);
Array.show(TableSize_40x);
exit();

selectWindow(Img_40x);
makePoint(getWidth()/2, getHeight()/2, "add");

// Calculate motor/pixel conversion factor in 10x coordinates
selectWindow(Img_10x);
m_Motor2Px_10x = MultiplyVectorVector(	newArray(getWidth(), getHeight()),
										newArray(1.0/TableSize_10x[0], 1.0/TableSize_10x[1]));
m_Motor2Px_10x = MultiplyVectorScalar(m_Motor2Px_10x, Math.pow(2, series_10x-1));		// convert factor to raw 10x dimensions 

// Find center of 10x Image in pixel coordinates
// Multipy the width of the 10x image with (2^series-1) to account for
// the fact that we are just using the downsampled image here
Center_10x = newArray(getWidth()/2, getHeight()/2);
makePoint(Center_10x[0], Center_10x[1], "add"); 			// show center of slide on displayed (downsampled) 10x image
Center_10x = MultiplyVectorScalar(Center_10x, Math.pow(2, series_10x-1)); 	// convert center coordinates to values for raw 10x image

// Find difference of motor coordinates between 10x and 40x image,
// convert it into 10x pixelunits and determine the center of the
// 40x image in units of 10x pixel coordinates
RelativeMotorPos = VectorSubtract(TablePos_10x, TablePos_40x);
RelativeMotorPos = MultiplyVectorVector(RelativeMotorPos, m_Motor2Px_10x);
PixelPos_40x = VectorSubtract(Center_10x, RelativeMotorPos);

selectWindow(Img_10x);
w = TableSize_40x[0] * m_Motor2Px_10x[0] / Math.pow(2, series_10x-1);
h = TableSize_40x[1] * m_Motor2Px_10x[1] / Math.pow(2, series_10x-1);
makePoint(PixelPos_40x[0] / Math.pow(2, series_10x-1), PixelPos_40x[1]/ Math.pow(2, series_10x-1), "add");
makeRectangle(PixelPos_40x[0] / Math.pow(2, series_10x-1) - w/2, PixelPos_40x[1] / Math.pow(2, series_10x-1) - h/2, w, h);
exit();

print("Conversion factor Motor-to-Pixels: " + d2s(m_Motor2Px, 3));
print("Identified location in 10x image: ["  + d2s(PixelPos_40x[0], 0) + 
										", " + d2s(PixelPos_40x[1], 0) + "]");

// Convert these pixel coordinates to tile coordinates
// (e.g. divide by the size of a tile multiplied with the factor by 
// which the analyzed image was downsampled for analysis)
PixelPos_40x_tile = MultiplyVectorScalar(PixelPos_40x, 1/(tilesize * Math.pow(2, series_SpotDet - 1)));
print("Identified location in tesellated 10x image: ["   + d2s(PixelPos_40x_tile[0], 0) + 
													", " + d2s(PixelPos_40x_tile[1], 0) + "]");

// Transform these pixel coordinates (spotdetection missing) according 
// to the elastix parameters
PixelPos_40x_tile_traf = TransformFromElastixFile(filename_trafo, PixelPos_40x_tile);
print("Identified location in transformed & tesellated 10x image: ["   + d2s(PixelPos_40x_tile_traf[0], 0) + 
																  ", " + d2s(PixelPos_40x_tile_traf[1], 0) + "]");


function TransformFromElastixFile(filename_trafo, vector){
	// Reads an elastix transform parameter file
	// Parses transform parameters (can be affine or similarity)
	// Applies transformation to 2D input vector

	// TODO: Test if result is plausible. If not, the the center of 
	// rotation may not be set correctly. See elastix manual under "2.6 Transforms"
	// for details on how to implement for the different transformations

	// Open transformation file as textstring
	filestring = File.openAsRawString(filename_trafo);
	rows = split(filestring, "\n");
	
	// get transformation parameters from line no. 3 of trafo file
	params = substring(rows[2], 1, lengthOf(rows[2])-1);
	params = split(params, " ");

	// Build transformation matrix depending on type of transformation:
	// Affine
	if (matches(rows[0], ".*Affine.*")) {
		a11 = parseFloat(params[1]);
		a12 = parseFloat(params[2]);
		a21 = parseFloat(params[3]);
		a22 = parseFloat(params[4]);
		M = newArray(a11, a12, a21, a22);
	}

	// Similarity
	if (matches(rows[0], ".*Similarity.*")) {
		s = parseFloat(params[1]);
		angle = parseFloat(params[2]);
		M = newArray(s * cos(angle),-s * sin(angle), s * sin(angle), s * cos(angle));
	}
	t = newArray(params[params.length-2], params[params.length-1]);	
	
	x = newArray(0, 0); 	// allocate output
	dim = vector.length;	// set dimension of matrix
	// multiply with input vector: x_out = M[2x2] * vector[2x1]
	for (i = 0; i < dim; i++) {
		for (j = 0; j < dim; j++) {
			x[i] = x[i] + M[i*dim + j] * vector[j]; 
		}
	}
	x = VectorAdd(x, t);		// add translation to return vector
	
	return x;
}

function SeriesOpen(filename, series){
	run("Bio-Formats Importer", "open=" + filename + " autoscale color_mode=Default rois_import=[ROI manager] view=Hyperstack stack_order=XYCZT series_"+series);
	run("Make Composite");
	name = File.nameWithoutExtension;
	rename(name);

	for (i = 1; i <= nSlices; i++) {
		setSlice(i);
		run("Enhance Contrast", "saturated=0.35");
	}
	
	return name;
}

function getMotorCenter(image){
	// reads motor coordinates of image from czi metadata
	Ext.setId(image);
	Ext.getMetadataValue("Information|Image|S|Scene|CenterPosition #1",pos);
	pos = split(pos, ",");
	for (i = 0; i < pos.length; i++) {
		pos[i] = parseFloat(pos[i]); // convert to number
	}
	return pos;	
}

function getMotorFrame(image){
	// reads image size in motor coordinates from czi metadata
	Ext.setId(image);
	Ext.getMetadataValue("Information|Image|SizeX #1",size_x);
	Ext.getMetadataValue("Information|Image|SizeY #1",size_y);
	size = newArray(size_x, size_y);
	for (i = 0; i < size.length; i++) {
		size[i] = parseFloat(size[i]); // convert to number
	}
	return size;	
}

function VectorSubtract(a, b){
	// difference between two vectors
	if (a.length != b.length) {
		print("Vectors must have same lengths!");
		return -1;
	}
	
	c = newArray(a.length);
	
	for (i = 0; i < a.length; i++) {
		c[i] = a[i] - b[i];
	}
	return c;
}

function VectorAdd(a, b){
	// difference between two vectors
	if (a.length != b.length) {
		print("Vectors must have same lengths!");
		return -1;
	}
	
	c = newArray(a.length);
	
	for (i = 0; i < a.length; i++) {
		c[i] = a[i] + b[i];
	}
	return c;
}

function MultiplyVectorVector(a, b){
	c = newArray(a.length);
	for (i = 0; i < a.length; i++) {
		c[i] = a[i] * b[i];
	}
	return c;
}

function MultiplyVectorScalar(a, b){
	c = newArray(a.length);
	for (i = 0; i < a.length; i++) {
		c[i] = a[i] * b;
	}
	return c;
}


