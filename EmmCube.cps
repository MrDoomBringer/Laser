
description = "HyperCube for Fusion360";
vendor = "Marlin";
vendorUrl = "https://github.com/MarlinFirmware/Marlin";

extension = "gcode";
setCodePage("ascii");

capabilities = CAPABILITY_INTERMEDIATE;
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = true;
allowedCircularPlanes = undefined; // allow any circular motion

// user-defined properties
properties = {
  startHomeX: false,
  startHomeY: false,
  startHomeZ: false,
  startPositionZ: "2",
  finishHomeX: false,
  finishPositionY: "",
  finishPositionZ: "",
  finishBeep: false,
  rapidTravelXY: 2500,
  rapidTravelZ: 300,
  laserEtch: "M106 S128",
  laserVaperize: "M106 S250",
  laserThrough: "M106 S250",
  laserOFF: "M107"
};

var xyzFormat = createFormat({decimals:3});
var feedFormat = createFormat({decimals:0});

var max_x = 0;
var max_y = 0;
var min_x = 500;
var min_y = 500;
var num_dupes_for_cutting = 3;

var xOutput = createVariable({prefix:"X"}, xyzFormat);
var yOutput = createVariable({prefix:"Y"}, xyzFormat);
var zOutput = createVariable({prefix:"Z"}, xyzFormat);
var feedOutput = createVariable({prefix:"F"}, feedFormat);
var planeOutput = createVariable({prefix:"G"}, feedFormat);

// circular output
var	iOutput	= createReferenceVariable({prefix:"I"}, xyzFormat);
var	jOutput	= createReferenceVariable({prefix:"J"}, xyzFormat);
var	kOutput	= createReferenceVariable({prefix:"K"}, xyzFormat);

var cuttingMode;
var be_duplicating = false;
var duplicate_code = "";

function formatComment(text) {
  return String(text).replace(/[\(\)]/g, "");
}

function writeComment(text) {
  writeWords(formatComment(text));
}

function onOpen() {
  writeln(";***********************************************************************************");
  writeln(";Emm's custom CAM post processor for Fusion360");
  writeln(";Based on the HyperCube CAM post processor By Tech2C")
  writeln(";***********************************************************************************");
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

/** Force output of X, Y, Z, and F on next output. */
function forceAny() {
  forceXYZ();
  feedOutput.reset();
}

function onSection() {
  if(isFirstSection()) {
    writeln("");
    writeWords("M117 Starting...");
    writeWords(properties.laserOFF, "         ;Laser/Fan OFF");
    writeWords("G21", "          ;Metric Values");
    writeWords(planeOutput.format(17), "          ;Plane XY");
    writeWords("G90", "          ;Absolute Positioning");
    writeWords("G28", " ;Home all axes");
    writeWords("G0 Z45.5 F2000", " ;Increase Z");
    writeWords("G0", feedOutput.format(properties.rapidTravelXY));
  }
  
  if (currentSection.getType() == TYPE_JET) {
    if(currentSection.jetMode == 0) {cuttingMode = properties.laserThrough }
	else if(currentSection.jetMode == 1) {cuttingMode = properties.laserEtch }
	else if(currentSection.jetMode == 2) {cuttingMode = properties.laserVaperize }
	else {cuttingMode = (properties.laserOFF + "         ;Unknown Laser Cutting Mode") }
  }
  
  if (hasParameter("operation-comment")) {
    var comment = getParameter("operation-comment");
    writeWords("M400");
    writeln("; " + comment);
    writeln("");
    if (comment.search("solo") == -1) { //If we're not solo, duplicate!
      be_duplicating = true;
    }
    else {
      be_duplicating = false;
    }
  }
  writeln("")
  writeln("; Mark Section Start")
}

function write_dupe() {
  if (be_duplicating){
    for (var i = 0; i < arguments.length; i++){
      duplicate_code += arguments[i] + " ";
    }
    duplicate_code += "\n";
  }
}

function onDwell(seconds) {
  if (seconds > 99999.999) {
    warning(localize("Dwelling time is out of range."));
  }
  seconds = clamp(0.001, seconds, 99999.999);
  writeWords("G4 S" + seconds, "        ;Dwell time");
  write_dupe("G4 S" + seconds, "        ;Dwell time");
}

function onPower(power) {
  if (power) { 
    writeWords(cuttingMode); 
    write_dupe(cuttingMode);
  }
  else { 
    writeWords(properties.laserOFF);
    write_dupe(properties.laserOFF); 
  }
  
  
}

function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y) {
    writeWords("G0", x, y, feedOutput.format(properties.rapidTravelXY));
    write_dupe("G0", x, y, feedOutput.format(properties.rapidTravelXY));
  }
  if (z) {
    writeWords("G0", z, feedOutput.format(properties.rapidTravelZ));
    write_dupe("G0", z, feedOutput.format(properties.rapidTravelZ));
  }
}

function check_f(f) {
  var new_f = f;
  if (new_f == "F1200")// && new_f != properties.rapidTravelXY) 
    new_f = "F500";
  return new_f;
}

function onLinear(_x, _y, _z, _feed) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var f = feedOutput.format(_feed);
  f = check_f(f)
  if(x || y || z) {
    writeWords("G1", x, y, z, f);
    write_dupe("G1", x, y, z, f);
  }
  else if (f) {
    writeWords("G1", f);
    write_dupe("G1", f);
  }
  if (_x > max_x)
    max_x = Math.ceil(_x);
  if (_y > max_y)
    max_y = Math.ceil(_y);
  if (_x < min_x)
    min_x = Math.floor(_x);
  if (_y < min_y)
    min_y = Math.floor(_y);
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  // one of X/Y and I/J are required and likewise
  var start = getCurrentPosition();
  
  switch (getCircularPlane()) {
  case PLANE_XY:
    writeWords(planeOutput.format(17), (clockwise ? "G2":"G3"), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), check_f(feedOutput.format(feed)));
    write_dupe(planeOutput.format(17), (clockwise ? "G2":"G3"), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), check_f(feedOutput.format(feed)));
    break;
  case PLANE_ZX:
    writeWords(planeOutput.format(18), (clockwise ? "G2":"G3"), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x, 0), kOutput.format(cz - start.z, 0), check_f(feedOutput.format(feed)));
    write_dupe(planeOutput.format(18), (clockwise ? "G2":"G3"), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x, 0), kOutput.format(cz - start.z, 0), check_f(feedOutput.format(feed)));
    break;
  case PLANE_YZ:
    writeWords(planeOutput.format(19), (clockwise ? "G2":"G3"), xOutput.format(x), yOutput.format(y), zOutput.format(z), jOutput.format(cy - start.y, 0), kOutput.format(cz - start.z, 0), check_f(feedOutput.format(feed)));
    write_dupe(planeOutput.format(19), (clockwise ? "G2":"G3"), xOutput.format(x), yOutput.format(y), zOutput.format(z), jOutput.format(cy - start.y, 0), kOutput.format(cz - start.z, 0), check_f(feedOutput.format(feed)));
    break;
  default:
    linearize(tolerance);
  }
}

function onSectionEnd() {
  writeWords(planeOutput.format(17));
  write_dupe(planeOutput.format(17));
  forceAny();
  writeWords(properties.laserOFF, "         ;Laser/Fan OFF");
  write_dupe(properties.laserOFF, "         ;Laser/Fan OFF");
  writeln("; Mark Section End")
  be_duplicating = false;
}

function onClose() {
  writeln("");
  for (var i = 0; i < num_dupes_for_cutting; i++){
    writeln("; Mark Duplicate Start [" + i + "]");
    writeln(duplicate_code);
    writeln("; Mark Duplicate End [" + i + "]");
  }
  writeWords("M400");
  writeWords(properties.laserOFF, "         ;Laser/Fan OFF");
  writeWords("M84", "          ;Motors OFF");
  writeWords("M300 S4698.63 P50");
  writeln("");
  writeln("; Mark Calibrate Start");
  writeln("M400");
  writeWords("M300 S4698.63 P50");
  writeln("G4 S1");
  writeln("; x:[" + min_x + ":" + max_x+ "] y:[" + min_y + ":" + max_y + "]");
  writeWords("G0",xOutput.format(min_x), yOutput.format(min_y), feedOutput.format(properties.rapidTravelXY));
  writeWords("G0",xOutput.format(max_x));
  writeWords("G0",yOutput.format(max_y));
  writeWords("G0",xOutput.format(min_x));
  writeWords("G0",yOutput.format(min_y));
  writeln("G4 S1");
  writeln("; Mark Calibrate End");
  writeln("");
}
