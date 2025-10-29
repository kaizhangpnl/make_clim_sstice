#!/bin/bash 
#SBATCH  --job-name=makesst
#SBATCH  --account=e3sm
#SBATCH  --nodes=1
#SBATCH  --output=sstice.o%j
#SBATCH  --exclusive
#SBATCH  --time=01:59:00
#SBATCH  --partition=debug
#............................................................................ 
# A complete procedure to derive SST and sea ice area coverage climatology 
# from v2.LR.piControl mpas-ocean and mpas-seaice monthly history output 
# to facilitate RFMIP simulations. 
#............................................................................ 

# activate e3sm_unified
source /lcrc/soft/climate/e3sm-unified/load_e3sm_unified_1.5.0_chrysalis.sh

# Extract monthly SST data, reset the path for history file and extracted sst as needed
 casename=v3.LR.piControl
 year1=0001
 year2=0500

 mkdir -p SSTDATA 
 mkdir -p IceAreaData

 for year in  `seq -f "%04g" $year1 $year2`; do
     for month in `seq -w 1 12`; do
         histfile=/lcrc/group/e3sm2/ac.golaz/E3SMv3/${casename}/archive/ocn/hist/$casename.mpaso.hist.am.timeSeriesStatsMonthly.$year-$month-01.nc
         sstfile=SSTDATA/mpaso.hist.am.timeSeriesStatsMonthly.$year-$month-01.nc
         rm -f $sstfile
         echo ncks -v timeMonthly_avg_activeTracers_temperature -d nVertLevels,0,0 $histfile $sstfile  
         ncks -v timeMonthly_avg_activeTracers_temperature -d nVertLevels,0,0 $histfile $sstfile & 
     done
     wait
 done

# Extract sea ice area coverage, reset the path as needed
 for year in  `seq -f "%04g" $year1 $year2`; do
     for month in `seq -w 1 12`; do
         histfile=/lcrc/group/e3sm2/ac.golaz/E3SMv3/${casename}/archive/ice/hist/$casename.mpassi.hist.am.timeSeriesStatsMonthly.$year-$month-01.nc
         icecovfile=IceAreaData/mpassi.hist.am.timeSeriesStatsMonthly.$year-$month-01.nc
         rm -f $icecovfile
         echo ncks -v timeMonthly_avg_iceAreaCell $histfile $icecovfile  
         ncks -v timeMonthly_avg_iceAreaCell $histfile $icecovfile & 
     done
     wait
 done

 mkdir -p climo/ocn
 mkdir -p climo/ice
  
 mkdir -p climo/0.5x0.5_bilin/ocn
 mkdir -p climo/0.5x0.5_bilin/ice
  
# compute climo, assuming climo/ocn and climo/ice exist
 ncclimo -m mpaso -s $year1 -e $year2 -i SSTDATA -o climo/ocn
 ncclimo -m mpassi -s $year1 -e $year2 -i IceAreaData -o climo/ice
 
# regrid the climo files and rename the SST and ice coverage variables
# reset the path for regridded data as needed. here use climo/0.5x0.5_bilin/ocn and ice
# mapfile=/lcrc/group/acme/public_html/diagnostics/mpas_analysis/maps/map_EC30to60E2r2_to_0.5x0.5degree_bilinear.nc
 mapfile=/lcrc/group/acme/public_html/diagnostics/mpas_analysis/maps/map_IcoswISC30E3r5_to_0.5x0.5degree_bilinear.nc
 for mon in  `seq -w 1 12`; do
     timerange=${year1}${mon}_${year2}${mon}
     sstfile=climo/ocn/mpaso_${mon}_${timerange}_climo.nc
     # remove dimension nVertLevels, by averaging over the dimension of size 1
     sstfile_noLevel=climo/ocn/mpaso_${mon}_${timerange}_climo.noLevel.nc
     rm -f $sstfile_noLevel
     ncwa -a nVertLevels $sstfile $sstfile_noLevel
     # rename the SST variable
     sstfile_ren=climo/ocn/SST_${mon}_${timerange}_climo.nc
     rm -f $sstfile_ren
     ncrename -v timeMonthly_avg_activeTracers_temperature,SST_cpl $sstfile_noLevel $sstfile_ren
     
     # regridding using 0.5x0.5_bilin map
     # in original orientation determined by the mapping file (the associated dst grid file)
     dstfile_WE=climo/0.5x0.5_bilin/ocn/${casename}_SST_${mon}_${timerange}_climo.WE.nc
      rm -f $dstfile_WE
      ncks --map $mapfile $sstfile_ren $dstfile_WE

     # rotate the hemispheres (WE -> EW)
     dstfile_EW=climo/0.5x0.5_bilin/ocn/${casename}_SST_${mon}_${timerange}_climo.nc
     echo ncks -O --msa -d lon,0.,180. -d lon,-180.,-0.1 $dstfile_WE $dstfile_EW
     rm -f $dstfile_EW
     ncks -O --msa -d lon,0.,180. -d lon,-180.,-0.1 $dstfile_WE $dstfile_EW

     # Reset the W. Hemisphere longitudes in 0-360 degree convention
     echo ncap2 -O -s 'where(lon < 0) lon=lon+360' $dstfile_EW $dstfile_EW
     ncap2 -O -s 'where(lon < 0) lon=lon+360' $dstfile_EW $dstfile_EW

     # The regridded data does not have _FillValue attribute; undefined/missing values default to 0
     # First set _FillValue attribute for variable SST_cpl with the value set to the default missing value
     #ncatted -a _FillValue,SST_cpl,a,f,0.0 $dstfile_EW
     ncatted -a _FillValue,SST_cpl,o,f,1.0e+36 $dstfile_EW

     # Then modify the _FillValue to be a large value 1.0e36, to distinigush from valid value
     # *** the following will cause double missing values assigned
     #ncatted -a _FillValue,SST_cpl,m,f,1.0e+36 $dstfile_EW

     # Ice Area Concentration, rename, regrid, and rotate the hemisphere
     icecovfile=climo/ice/mpassi_${mon}_${timerange}_climo.nc
     icecovfile_ren=climo/ice/iceArea_${mon}_${timerange}_climo.nc
     echo ncrename -v timeMonthly_avg_iceAreaCell,ice_cov $icecovfile $icecovfile_ren
     ncrename -v timeMonthly_avg_iceAreaCell,ice_cov $icecovfile $icecovfile_ren

     dstfile_WE=climo/0.5x0.5_bilin/ice/${casename}_iceArea_${mon}_${timerange}_climo.WE.nc
     dstfile_EW=climo/0.5x0.5_bilin/ice/${casename}_iceArea_${mon}_${timerange}_climo.nc

     rm -f $dstfile_WE
     ncks --map $mapfile $icecovfile_ren $dstfile_WE
     rm -f $dstfile_EW
     ncks -O --msa -d lon,0.,180. -d lon,-180.,-0.1 $dstfile_WE $dstfile_EW
     ncap2 -O -s 'where(lon < 0) lon=lon+360' $dstfile_EW $dstfile_EW
done
 # concatenate monthly climo into a single file
 WKDIR=`pwd`
 cd climo/0.5x0.5_bilin/ocn
 rm -f ${casename}_SST_climo_${year1}-${year2}.nc
 ncrcat ${casename}_SST_??_*_climo.nc -o ${casename}_SST_climo_${year1}-${year2}.nc
 # rename Time dimension to time as assumed in later step
 ncrename -d Time,time ${casename}_SST_climo_${year1}-${year2}.nc

 cd $WKDIR
 cd climo/0.5x0.5_bilin/ice
 rm -f ${casename}_iceArea_climo_${year1}-${year2}.nc
 ncrcat ${casename}_iceArea_??_*_climo.nc -o ${casename}_iceArea_climo_${year1}-${year2}.nc
 ncrename -d Time,time ${casename}_iceArea_climo_${year1}-${year2}.nc

 # add _fillvalue attribute for variable ice_cov. filling for land grids will refer to this fillvalue
 ncatted -a_FillValue,ice_cov,a,f,1.0e36 ${casename}_iceArea_climo_${year1}-${year2}.nc

 # Diddling and consistency check of SST and Sea Ice: based on a ncl script provided by Jim Benedict

 # Adjust SST and ice area concentration to ensure monthly mean of runtime temporally interpolated data
 #        data will equal to the actual prescribed monthly data

 cd $WKDIR

 # set and pass env variable to ncl diddling program

 export INPUT_SST_FILE=climo/0.5x0.5_bilin/ocn/${casename}_SST_climo_${year1}-${year2}.nc
 export INPUT_SEAICE_FILE=climo/0.5x0.5_bilin/ice/${casename}_iceArea_climo_${year1}-${year2}.nc
 export OUTPUT_SSTICE_FILE=sst_ice_${casename}_0.5x0.5_climo_${year1}-${year2}.nc
 export caseName=$casename

 # Set path to NCL, may do
 # 1. "module load ncl" if available as module
 # 2. "conda activate ncl_stable"   if installed in a conda environment
 # 3.  export NCARG_ROOT=/soft/bebop/ncl/6.6.2  tell where to find ncl if installed in regular shell env

 conda activate ncl_stable

 ncl < sst_ice_climo_diddle.ncl | tee log.diddling_consistency

 conda deactivate
 # reactivate e3sm_unified
  source /lcrc/soft/climate/e3sm-unified/load_e3sm_unified_1.5.0_chrysalis.sh
 #
 # derive domain file from the generated SSTICE data 
  cdate=`date +%y%m%d`
  domainOcnFile=domain.ocn.0.5x0.5.c$cdate.nc
  ncks -M -v lat,lon sst_ice_${casename}_0.5x0.5_climo_${year1}-${year2}.nc $domainOcnFile
  ncrename -v lat,yc -v lon,xc $domainOcnFile

