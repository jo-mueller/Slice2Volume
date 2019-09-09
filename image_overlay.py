# -*- coding: utf-8 -*-
"""
Created on Thu Sep  5 10:51:29 2019

@author: Johannes
"""

import os, tqdm, tifffile
import numpy as np
import pydicom as dcm
import matplotlib.pyplot as plt

def load_dcm_series(path):
    "store image series from one directory in one array"
    
    filelist = os.listdir(path)
    
    # get metadata from one file
    for element in filelist:
        if element.endswith('.dcm'):
            meta  = dcm.read_file(os.path.join(path, filelist[0]))
            break
        else:
            continue
    
    # store data in array
    Array = np.zeros((meta.Rows, meta.Columns, len(filelist)))
    
    for i in tqdm.tqdm(range(len(filelist))):        
        meta  = dcm.read_file(os.path.join(path, filelist[i]))
        Array[:,:, i] = meta.pixel_array        
    
    return Array, meta

    

root = os.getcwd()
CT_path = os.path.join(root, 'C3H_3', 'CT')
Dose_path = os.path.join(root, 'C3H_3', 'DoseMap')
dosefile = os.path.join(root, 'C3H_3', 'CT_C3H-3_Dose.dcm')


#read CT data
array_CT, meta_CT = load_dcm_series(CT_path)

# read dose data
meta_dose  =  dcm.read_file(dosefile)
array_dose =  meta_dose.pixel_array

# zero_pad dose array to adjust dimensions
start_slice = 287
stop_slice  = 377

array_dose_new = np.zeros_like(array_CT)
for z in range(np.shape(array_CT)[2]):
    if start_slice<z<stop_slice:
        array_dose_new[:,:,z] = array_dose[z-start_slice,:,:]

# write dosemap to tiff
tifffile.imsave(os.path.join(root, 'C3H_3', 'DoseMap_full.tiff'),
                array_dose_new.astype('float32'))


#meta_dose.PixelData = array_dose_new.tostring()

#dcm.write_file(os.path.join(root, 'C3H_3', 'CT_C3H-3_Dose_full_array.dcm'),
#               meta_dose, write_like_original=False)
# determmining position of histo slide in brain
#top_brain = 185
#bottom_brain = 245
#
#slice_thickness = 0.1 #100 microns histo slice distance
#n_slice         = 20 # slice No. X from top of brain
#
#dist_from_top = n_slice*slice_thickness/float(meta_CT.PixelSpacing[0])
#y       = int(top_brain + dist_from_top)
#y_slice = array_CT[y, :,:]
#tifffile.imsave(os.path.join(root, 'C3H_3', 'y_{:3d}.tiff'.format(y)), 
#                y_slice.astype('float32'))



