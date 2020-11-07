//this command is needed to access the metadata via bio-formats
run("Bio-Formats Macro Extensions");

//specify the file
filename = "E:/P1/2020-0528/P1_C3H_M13_foci_P1.czi";

//open and extract the table position
run("Bio-Formats","open=" + filename + " color_mode=Composite rois_import=[ROI manager] view=Hyperstack stack_order=XYCZT" );
Ext.setId(filename);
Ext.getMetadataValue("Information|Image|S|Scene|CenterPosition #1",position_xy);

//write the Table position into a table
//the lenght unit is micrometer, x and y are separated via a comma
Table.create("Position");
Table.set("x_y/micrometer", 0, position_xy); 