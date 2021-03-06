# /////////////////////////////////////////////////////////////////////////
## Global map with pollen limitation studies
# /////////////////////////////////////////////////////////////////////////

rm(list = ls(all.names = TRUE)); gc(reset = TRUE)

library(rgdal)
library(sp)
library(data.table)
library(ggplot2)
library(mapview)


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Read & prepare data -----------------------------------------------------
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Read PL data (the output of the Prepare_data.R script). Select only the needed
# columns.
ES_dt <- fread("Output/GloPL_with_id_updated_ES.csv", 
               colClasses = "character",
               na.strings = c("NA","N/A","null", ""),
               select = c("unique_number", "Longitude", "Latitude"))

# Transform longitude to numeric
ES_dt[, lon := as.numeric(Longitude)]

# Transform latitude to numeric
ES_dt[, lat := as.numeric(Latitude)]

# Are the coordinates within expected ranges?
range(ES_dt[,lon]) %between% c(-180, 180)
range(ES_dt[,lat]) %between% c(-90, 90)


# Transform unprojected long-lat in Robinson coordinates
ES_dt[, c("X.prj","Y.prj") := data.table(rgdal::project(xy   = cbind(lon, lat),
                                                        proj = "+init=ESRI:54030"))]
# "+init=ESRI:54030" same as "+proj=robin"

# Check points with interactive map
points_WGS84 <- sp::SpatialPointsDataFrame(coords      = ES_dt[,.(lon, lat)], # order matters
                                           data        = ES_dt[,.(unique_number)], 
                                           proj4string = CRS("+proj=longlat +datum=WGS84 +ellps=WGS84 +towgs84=0,0,0"))
html_map <- mapview(points_WGS84)
# save as html
mapshot(html_map, url = "Global_map.html")


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Load & prepare NaturalEarth shapefiles ----------------------------------
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

load("Data/NaturalEarth.RData"); setDT(lbl.Y); setDT(lbl.X)
# Details about NaturalEarth shapefiles:
#   The files were already downloaded from http://www.naturalearthdata.com/
#   Graticules were adjusted to 10 dg for latitude lines and 20 dg for longitude lines 
#  (some editing was carried in ArcMap)

# Project from long-lat (unprojected) to Robinson projection
NE_countries_rob  <- spTransform(NE_countries, CRS("+proj=robin"))
NE_graticules_rob <- spTransform(NE_graticules, CRS("+proj=robin"))
NE_box_rob        <- spTransform(NE_box, CRS("+proj=robin"))

# Shift longitude of OX graticule labales. This was needed because, for example,
# the 160 dg label ended up on the 180 longitude line when projecting to
# Robinson. A shift is applied for each degree in the sequence 
# seq(from = 160, to = 0, by = -20)
shift <- c(10, 10, 9, 8, 8, 5, 2, 0, 0)
lbl.X[, shift := rep(c(shift, -rev(shift)[-1]), 2)]
lbl.X
lbl.X[, lon := lon - shift] # apply shift
lbl.X[, shift := NULL] # delete column

# Project the labales for graticules to Robinson
lbl.Y[, c("X.prj","Y.prj") := data.table(rgdal::project(xy   = cbind(lon, lat),
                                                        proj = "+proj=robin"))]
lbl.X[, c("X.prj","Y.prj") := data.table(rgdal::project(xy   = cbind(lon, lat),
                                                        proj = "+proj=robin"))]
# Create helper columns with nudged coordinates for plotting graticule labeles.
# For lbl.Y nudge longitude and for lbl.X nudge latitude.
# Give nudge values in dg (if you change, re-run also the projection lines above)
my_nudge <- cbind(nudge_lon = 10, 
                  nudge_lat = 4) 
my_nudge <- rgdal::project(my_nudge, proj = "+proj=robin")
lbl.Y[, X.prj := ifelse(lon < 0, 
                        yes = X.prj - my_nudge[1,1], 
                        no = X.prj + my_nudge[1,1])]
lbl.X[, Y.prj := ifelse(lat < 0, 
                        yes = Y.prj - my_nudge[1,2], 
                        no = Y.prj + my_nudge[1,2])]


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Plot map ----------------------------------------------------------------
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# ... Prepare base map ----------------------------------------------------

base_map <- 
    ggplot() +
    # ___ add graticules projected to Robinson
    geom_path(data = NE_graticules_rob, 
              aes(x     = long, 
                  y     = lat, 
                  group = group), 
              linetype = "dotted", 
              color    = "grey50", 
              size     = 0.1) +
    # ___ add Natural Earth countries projected to Robinson
    geom_polygon(data = NE_countries_rob, 
                 aes(x     = long,
                     y     = lat, 
                     group = group), 
                 colour = "grey60", # country border color
                 fill   = "gray90", # country fill color
                 size   = 0.2) +
    # ___ add graticule labels - latitude and longitude
    geom_text(data = lbl.Y, 
              aes(x     = X.prj, 
                  y     = Y.prj, 
                  label = lbl), 
              color   = "grey50", 
              size    = 1) +
    geom_text(data = lbl.X, 
              aes(x     = X.prj, 
                  y     = Y.prj, 
                  label = lbl), 
              color   = "grey50", 
              size    = 1) +
    # ___ add Natural Earth box projected to Robinson
    geom_polygon(data = NE_box_rob, 
                 aes(x = long, 
                     y = lat), 
                 colour ="black", 
                 fill   ="transparent", 
                 size   = 0.2) +
    # "Regions defined for each Polygons" warning has to do with fortify
    # transformation. Might get deprecated in future.
    # ___ the default ratio = 1 in coord_fixed ensures that one unit on the x-axis 
    # is the same length as one unit on the y-axis
    coord_fixed(ratio = 1) +
    # ___ remove the background and default gridlines
    theme_void()


# ... Add study locations (points) ----------------------------------------

glopl_map <- base_map +
    # ___ add the XY points
    geom_point(data = ES_dt, 
               aes(x = X.prj, 
                   y = Y.prj),
               color = "black",
               size  = 0.5,
               shape = 1,
               alpha = 1/2) +
    # Adjust theme components
    theme(
        # Set font size & family - affects legend only 
        # "sans" = "Arial" and is the default on Windows OS; check windowsFonts()
        text = element_text(size = 8, family = "sans"),
        # Grab bottom-right (x=1, y=0) legend corner 
        legend.justification = c(1, 0),
        # and position it in the bottom-right plot area.
        legend.position = c(1.05, 0.05),
        legend.margin = margin(t = 0, r = 0, b = 0, l = 0),
        # Set height of legend items (keys).
        legend.key.height = unit(3, "mm"),
        # Set margin around entire plot.
        plot.margin = unit(c(t = 0, r = 0.8, b = 0, l = -0.5), "cm")
    )


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Save as pdf and png file ------------------------------------------------
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

ggsave(plot = glopl_map, 
       filename = "Output/Global_map_draft_11.pdf", 
       width = 14, 
       height = 7, 
       units = "cm")

ggsave(plot = glopl_map, 
       filename = "Output/Global_map_draft_11.png", 
       width = 14, 
       height = 7, 
       units = "cm", 
       dpi = 1000)
