# To see options, run: 'uperl CoreMetrics.pl -help'
# Version Info
#
# 1.0 First Versioned Release 2016-12-20
# 1.1 Fix minor bug on Windows where it wouldn't open the graph if there was a space in the path
# 1.2 Add 4 additional metric threshholds, fix issue with nasted directories in Architect view  2016-12-29
# 1.3 Add Metrics csv, remove standard system classes from calcuations
# 1.4 Add separate class metric export, only generate metrics on real classes defined in project, all line counts are based on loc, not raw lines
# 1.5 Add LOC for class metrics export, show # of classes
# 1.6 Add architecture type to class metric export
# 1.7 Change some of the default values
# 1.8 Fix bug with Borderline Core-Periphery if there was only one cyclic group. Also add Central Size metric.
# 1.9 For empty file aggregate metrics export zero instead of blank
# 1.10 Fix Central Size metric pointing to core, add core and central for all projects
our $version = "1.10";

use strict;
use Data::Dumper;
use List::Util qw( min max sum);
use File::Basename;
use Getopt::Long;
use Understand;

#************************** Globals *****************************
our $abort_called;
our @visibilityMatrix;
our @stack;
our $index;
our $analyzedCount; #How many files have been analyzed;
our %fileObjsByEntID; #hash of the same file objects by entityid
our $fileCount;
our $percentComplete;
my $dbPath;
my $help;
my %options;


#************************* Main *********************************
my $report = convertIreport->new();
init($report);
setupOptions();
generate($report);


sub generate {
  my $report = shift;
  
  $abort_called=0;
  @visibilityMatrix=();
  @stack=();
  $index=0;
  $analyzedCount=0; #How many files have been analyzed;
  %fileObjsByEntID=(); #hash of the file objects by entityid
  $fileCount=0;
  $percentComplete=0;
  my $start_run = time();
  $percentComplete=0;
  $analyzedCount=0;
  my $outputDir = $report->option->lookup("outputDir");
  my $createTestFiles = $report->option->lookup("createTestFiles");
  my $createMetricsFiles = $report->option->lookup("createMetrics");
  my $createArch = $report->option->lookup("createArch");
  my $maxFileSize = $report->option->lookup("MaxFileSize");
  my $maxFunctionSize = $report->option->lookup("MaxFuncSize");
  my $maxCBO = $report->option->lookup("MaxCBO");
  my $maxWMC=$report->option->lookup("MaxWMC");
  my $maxWMCM=$report->option->lookup("MaxWMCM");
  my $maxRFC=$report->option->lookup("MaxRFC");
  
  
  my $outputFileName;
  my $largeFunctionCount=0;
  my $largeFileCount = 0;
  my $slash = "/";
  $slash = "\\" if $^O eq 'MSWin32';
  my %directoryList;
  my @fileLines;
  
  
  #Check file locations
  if (! $outputDir){
    die usage("Specify Output Directory in options to save files\n");
  }elsif($outputDir){
    my $success = mkdir("$outputDir");
    if (!$success && ! -e $outputDir){
      die usage("Could not create $outputDir, $!\n");
    }
  }
  
  #Get the project name and path
  add_progress($report,.005,"Initializing");
  #$report->progress(1,"Initializing");
  $report->db->name() =~ /(.*[\/\\])([^\/\\]*)\.udb/;
  my $projectName = ucfirst($2);
  

  # Initialize the initial data structures
  my @fileObjList; # List of file objects sorted alphabetically by directory name
  my @titlesList; #An array of file names in alpha order for printing the DSM and visibility Matrix

  my $count=0;

  add_progress($report,.015,"Analyzing dependencies");
  my @fileEnts = sort {dirname($a->relname) cmp dirname($b->relname)|| $a->relname cmp $b->relname} $report->db->ents("file ~unknown ~unresolved");
  foreach my $fileEnt (@fileEnts){
    add_progress($report,.02*10/scalar @fileEnts,"Analyzing dependencies") unless $count % 10;
    Understand::Gui::yield();
    next if $fileEnt->library();
    return if $abort_called;
    my $loc = $fileEnt->metric("CountLineCode");
    push @fileLines,$loc;
    $largeFileCount++ if $loc >$maxFileSize;
    my $fileObj = new fileObj($count,$fileEnt);
    $fileObjList[$count] = $fileObj;
	$titlesList[$count] = $fileObj->{relname};
    $fileObj->{loc} = $loc;
    $fileObj->{commentToCode} = $fileEnt->metric("RatioCommentToCode");
    $fileObjsByEntID{$fileObj->{entid}}= $fileObj;  #Create a hash to easily lookup the order of each file
    my $depends = $fileEnt->depends;
    if ($depends){
      foreach my $depEnt ($depends->keys()){
        if ($depends->value($depEnt)){
          push @{$fileObj->{depends}},$depEnt->id;
        }
      }
    }
    #add directory information
    my $directory = dirname($fileEnt->relname());
    $directory =~ s'\\'\\\\'g;
    $directoryList{$directory}{"first"}=$count unless $directoryList{$directory}{"size"};
    $directoryList{$directory}{"size"}++;
    $count++;
  }
  $fileCount = scalar @fileObjList; #Number of files in the project
  


  #Populate Design Structure Matrix for each file based off of Understand dependencies
  my @designStructureMatrix; #Array holding the DSM
  foreach my $fileObj (@fileObjList){
    foreach my $depID (@{$fileObj->{depends}}){
        $designStructureMatrix[$fileObj->{id}][$fileObjsByEntID{$depID}->{id}]= 1;
    }             
  }

  if($createTestFiles){
    #Print the Design Structure matrix to an output file
    add_progress($report,.02,"Saving DSM to output file");
    Understand::Gui::yield();
    return if $abort_called;
    $outputFileName = $outputDir."\\1. $projectName Initial Design Structure Matrix.txt";
    printSquareMatrix(\@titlesList ,\@designStructureMatrix,$outputFileName);
  }

  # Calculate the  Transitive Closure via depth first traversal, also the Visibility Fan ins and outs
  printprogress($report,.10,"Calculating Transitive Closure");
  for (my $k = 0; $k < $fileCount; $k++){
    strongconnect($report,$fileObjList[$k]) unless $fileObjList[$k]->{index};
    
  }
    for (my $i = 0; $i < $fileCount; $i++){
      for (my $j = 0; $j < $fileCount; $j++){
        $fileObjList[$j]->vfiInc if $visibilityMatrix[$i][$j];
        $fileObjList[$i]->vfoInc if $visibilityMatrix[$i][$j];
    }
  }

  if($createTestFiles){
    #Print the Transitive Structure matrix to an output file
    add_progress($report,.02,"Print the Transitive Structure matrix to an output file");
    Understand::Gui::yield();
    return if $abort_called;
    $outputFileName = $outputDir."\\2. $projectName Visibility Matrix.txt";
    printSquareMatrix(\@titlesList ,\@visibilityMatrix,$outputFileName);
   
  }

  printprogress($report,.85,"Identifying Cyclic Groups");

  #Identify the cyclic groups of the system and identify the largest.
  my %cyclicGroups; #The cyclic group id for each file
  my @sorted = sort {$b->{vfi} <=> $a->{vfi} || $a->{vfo} <=> $b->{vfo} } @fileObjList;
  my @m;
  my $prev;
  my $curGroup=1; 
  my $counter =0;
  foreach my $file (@sorted){
    if (! $prev  || $file->{vfi} == 1 || $file->{vfo} == 1 
          || $file->{vfi} != $prev->{vfi} || $file->{vfo} != $prev->{vfo}){
        $m[$counter]=1;
    }
    elsif ($file->{vfi} > 1 && $file->{vfo} >1 
         && $file->{vfi} == $prev->{vfi} && $file->{vfo} == $prev->{vfo}){
      $m[$counter]=$m[$counter-1]+1;
    }
    
    #This item consitutes the begining of a new cyclic group, label the previous group
    if ($m[$counter]<$m[$counter-1]){
      my $sizeN = min ($m[$counter-1],$prev->{vfi},$prev->{vfo});
      for( my $i=$m[$counter-1];$i>=1;$i--){
        $sorted[$counter-$i]->{group} = $curGroup
      }
      $cyclicGroups{$curGroup}{size}=$sizeN;
      $cyclicGroups{$curGroup}{vfi}= $prev->{vfi};
      $cyclicGroups{$curGroup}{vfo}= $prev->{vfo};
      $curGroup++;
    }
    
    $prev = $file;
    $counter++;
  }

  if($createTestFiles){   
    $outputFileName = $outputDir."\\3. $projectName Visibility Fan In and Out.txt";
    my $length = length longestItem(@titlesList);
    open (FILE,'>',"$outputFileName") || die ("Couldn't open $outputFileName $!\n");
      print FILE sprintf("%${length}s VFI VFO  Group   Size\n",'');
      foreach my $file (sort{$b->{vfi} <=> $a->{vfi} || $a->{vfo} <=> $b->{vfo} ;}@fileObjList){
        my $group =$file->{group};
        my $groupSize;
        $groupSize = $cyclicGroups{$group}{size} if $group;
        print FILE sprintf("%${length}s  %d   %d     %s      %s\n", $file->{relname},$file->{vfi},$file->{vfo},$group,$groupSize);
      }
      close FILE;
  }

  #Determine the Architecture type of the project
  my $projectArchitectType = "Hierarchical"; #default
  my $coreGroup;
  my $largestGroupID;
  if (%cyclicGroups){
    #Find the largest and second largest Groups
    my @orderedGroupIDs = sort {$cyclicGroups{$b}{size} <=> $cyclicGroups{$a}{size}}  keys %cyclicGroups;
    $largestGroupID = $orderedGroupIDs[0] if @orderedGroupIDs;
    my $secondLargestID= $orderedGroupIDs[1] if scalar @orderedGroupIDs > 1;
    
    if ($cyclicGroups{$largestGroupID}{size} >= $fileCount *.04){
      $projectArchitectType = "Multi-Core";
      if (! $secondLargestID || $cyclicGroups{$largestGroupID}{size} >= $cyclicGroups{$secondLargestID}{size} * 1.5){
        $projectArchitectType = "Borderline Core-Periphery";
        $coreGroup = $largestGroupID;
      }
    }
    if ($cyclicGroups{$largestGroupID}{size} >= $fileCount *.06){
      $projectArchitectType = "Core-Periphery";
      $coreGroup = $largestGroupID;
    }
  }

  #Median Partition Component Types
  #First calculate the median VFI and VFO
  my @vfoList;
  my @vfiList;
  foreach my $file (@fileObjList){
    push @vfoList,$file->{vfo};
    push @vfiList,$file->{vfi};
  }
  my $VFIm = median(@vfiList);
  my $VFOm = median(@vfoList);
  my %mGroupSize;
  foreach my $file (@fileObjList){
    if($file->{vfi} == 1 && $file->{vfo} ==1){
      $file->{componentM} = "Isolate";
      $mGroupSize{Isolate}++;
    }elsif ($file->{vfi}>= $VFIm && $file->{vfo}< $VFOm){
      $file->{componentM} = "Shared";
      $mGroupSize{Shared}++;
    }elsif ($file->{vfi}>= $VFIm && $file->{vfo}>= $VFOm){
        $file->{componentM} = "Core";
        $mGroupSize{Core}++;
    }elsif ($file->{vfi}< $VFIm && $file->{vfo} < $VFOm){
        $file->{componentM} = "Peripheral";
        $mGroupSize{Peripheral}++;
    }elsif($file->{vfi}< $VFIm && $file->{vfo} >= $VFOm){
        $file->{componentM} = "Control";
        $mGroupSize{Control}++;
    }
  }

  #Create a new DSM based off the Median View
  my @medianOrderedObjectList = sort sortByMedian @fileObjList;
  my @medianDSM;
  my @medianTitles;
  $count=0;
  my %medianOrderedObjectByEntID;
  foreach my $file (@medianOrderedObjectList){
    $medianOrderedObjectByEntID{$file->{entid}}=$count;
    $file->{medianOrder}=$count;
    $medianTitles[$count] = $file->{relname}." [".$file->{componentM}."]";
    $count++;
  }
  $count=0;
  foreach my $file (@medianOrderedObjectList){
    foreach my $dep (@{$file->{depends}}){
      return if $abort_called;
      Understand::Gui::yield();
      $medianDSM[$count][$medianOrderedObjectByEntID{$dep}]= 1;
    }
    $count++;    
  }
  $count=0;

  if($createTestFiles){
    #Print the Median matrix to an output file
    add_progress($report,.02,"Print the Median matrix to an output file");
    return if $abort_called;
    Understand::Gui::yield();
    $outputFileName = $outputDir."\\4. $projectName Median Matrix.txt";
    printSquareMatrix(\@medianTitles ,\@medianDSM,$outputFileName);
  }

  
  #determine if the project has a Core-Periphery Group
  
  my %cpGroupSize;
  if ( $coreGroup){
    add_progress($report,.04,"Analyzing Core-Periphery Group");
    return if $abort_called;
    Understand::Gui::yield();
    #Core-Periphery Partition
    my $VFIc = $cyclicGroups{$coreGroup}{vfi};
    my $VFOc = $cyclicGroups{$coreGroup}{vfo};
    foreach my $file (@fileObjList){
      if($file->{vfi} == 1 && $file->{vfo} ==1){
        $file->{componentCP} = "Isolate";
        $cpGroupSize{Isolate}++;
      }elsif ($file->{group} == $coreGroup){
        $file->{componentCP} = "Core";
        $cpGroupSize{Core}++;
      }elsif ($file->{vfi}>= $VFIc && $file->{vfo}< $VFOc){
          $file->{componentCP} = "Shared";
          $cpGroupSize{Shared}++;
      }elsif ($file->{vfi}< $VFIc && $file->{vfo} < $VFOc){
          $file->{componentCP} = "Peripheral";
          $cpGroupSize{Peripheral}++;
      }elsif($file->{vfi}< $VFIc && $file->{vfo} >= $VFOc){
          $file->{componentCP} = "Control";
          $cpGroupSize{Control}++;
      }
    }
    
    
    
    #Create a new DSM based off the Core-Periphery View
    my @coreOrderedObjectList = sort sortByCorePeriphery @fileObjList;
    my @corePeripheryDSM;
    my @coreTitles;
    $count=0;
    my %coreOrderedObjectsByEntID;
    foreach my $file (@coreOrderedObjectList){
      $file->{coreOrder}=$count;
      $coreOrderedObjectsByEntID{$file->{entid}}=$count;
      $coreTitles[$count] = $file->{relname}." [".$file->{componentCP}."]";
      $count++;
    }
    $count=0;
    foreach my $file (@coreOrderedObjectList){
      foreach my $dep (@{$file->{depends}}){
        $corePeripheryDSM[$count][$coreOrderedObjectsByEntID{$dep}]= 1;
      }
      $count++;    
    }
    if($createTestFiles){
    #Print the Core-Periphery matrix to an output file
      add_progress($report,.02,"Print the Core-Periphery matrix to an output file");
      return if $abort_called;
      Understand::Gui::yield();
      $outputFileName = $outputDir."\\5. $projectName Core-Periphery Matrix.txt";
      printSquareMatrix(\@coreTitles ,\@corePeripheryDSM,$outputFileName);
    }
  }
  
  #Calculate Metrics
  printprogress($report,.95,"Calculating Metrics");
  #Function metric calculation
  foreach my $funcEnt ($report->db->ents("function ~unknown ~unresolved, method ~unknown ~unresolved")){
    $largeFunctionCount++ if $funcEnt->metric("CountLineCode")>$maxFunctionSize;
  }
  #class Metric calculation
  my @cbos;
  my $cbosOver;
  my @wmcs;
  my $wmcsOver;
  my @wcmcyclos;
  my $wmccyclosOver;
  my @rfcs;
  my $rfcsOver;
  my $classCount;
  if ($createMetricsFiles){
    my $csvFile = $outputDir.$slash."classMetrics.csv";
    open (FILE,'>',$csvFile) || die ("Couldn't open $csvFile $!\n");
    print FILE "Class, Kind, Filename, CBO, WMC, WMC-McCabe, RFC, LOC, Median Group, CP Group\n";
  }
   
  #Loop through each class to generate the class metrics
  foreach my $class (sort{lc($a->longname()) cmp lc($b->longname());} $report->db->ents("class ~unknown ~unresolved ~unnamed,interface ~unknown ~unresolved ~unnamed, struct ~unknown ~unresolved ~unnamed, union ~unknown ~unresolved ~unnamed")){
    next if $class->library();
    my $declRef = getDeclRef($class);
    next unless $declRef;
    my $cbo =$class->metric("CountClassCoupled");
    my $wmc =$class->metric("CountDeclMethod");
    my $wmcm = $class->metric("SumCyclomatic");
    my $rfc = $class->metric("CountDeclMethodAll")+getCalledMethodCount($class);
    my $loc = $class->metric("CountLineCode");
    push (@cbos,scalar($cbo));
    push (@wmcs,scalar($wmc));
    push (@wcmcyclos,scalar($wmcm));
    push (@rfcs,scalar($rfc));
    $cbosOver++ if $cbo > $maxCBO;
    $wmcsOver++ if $wmc > $maxWMC;
    $wmccyclosOver++ if $wmcm > $maxWMCM;
    $rfcsOver++ if $rfc > $maxRFC;
    $classCount++;
    if($createMetricsFiles){ # If generating the metrics file associate the max class metric with the file
      my $declFile = $declRef->file;
      my $filename = $declFile->longname(1);
      my $fileObj = $fileObjsByEntID{$declFile->id()};
      print FILE '"'.$class->longname."\",\"".$class->kindname."\",\"$filename\",$cbo,$wmc,$wmcm,$rfc,$loc,".$fileObj->{componentM}.",".$fileObj->{componentCP}."\n";
        $fileObj->{maxCBO} = $fileObj->{maxCBO} < $cbo ? $cbo : $fileObj->{maxCBO};
        $fileObj->{maxWMC} = $fileObj->{maxWMC} < $wmc ? $wmc : $fileObj->{maxWMC};
        $fileObj->{maxWMCM} =$fileObj->{maxWMCM} < $wmcm ? $wmcm : $fileObj->{maxWMCM};
        $fileObj->{maxRFC} = $fileObj->{maxRFC} < $rfc ? $rfc : $fileObj->{maxRFC};
    }
  }
  close(FILE) if $createMetricsFiles;
  
  #Export the per file metrics
  if($createMetricsFiles){
    my $csvString = "Filename, LOC, CommentToCodeRatio, MaxCBO, MaxWMC, MaxWMC-McCabe, MaxRFC, Median Group, CP Group\n";
    foreach my $file (@fileObjList){
      $csvString .= '"'.$file->{longname}.'",';
      $csvString .= $file->{loc}.",";
      $csvString .= $file->{commentToCode}.",";
      $csvString .= ($file->{maxCBO}?$file->{maxCBO}:"0") .",";
      $csvString .= ($file->{maxWMC}?$file->{maxWMC}:"0").",";
      $csvString .= ($file->{maxWMCM}?$file->{maxWMCM}:"0").",";
      $csvString .= ($file->{maxRFC}?$file->{maxRFC}:"0").",";
      $csvString .= $file->{componentM}.",";
      $csvString .= $file->{componentCP}."\n";
    }
    my $csvFile = $outputDir.$slash."fileMetrics.csv";
    open (FILE,'>',$csvFile) || die ("Couldn't open $csvFile $!\n");
    print FILE  $csvString ;
    close FILE;
  }
  
  
  my @metrics;
  my @metricNames;
  push @metrics,$projectName;
  push @metricNames,"Project Name";
  push @metrics, sprintf("%.1f",((sum @vfoList) *100/($fileCount * $fileCount))) if $fileCount;
  push @metricNames,"Propagation Cost" if $fileCount;;
  push @metrics,$projectArchitectType;
  push @metricNames,"Architecture Type";
  if ($fileCount){
    push @metrics, sprintf("%.1f%",($cyclicGroups{$largestGroupID}{size}*100/$fileCount));
    push @metricNames,"Core Size";
    push @metrics, sprintf("%.1f%",($mGroupSize{Core}*100/$fileCount));
    push @metricNames,"Central Size";
  }
  
  push @metrics, $report->db->metric("CountLineCode");
  push @metricNames,"Lines of Code (LOC)";
  push @metrics, ($report->db->metric("RatioCommentToCode")*100)."%";
  push @metricNames,"Comment/Code Ratio";
  push @metrics,$classCount;
  push @metricNames,"Classes";
  push @metrics,$fileCount;
  push @metricNames,"Files";
  push @metrics,median(@fileLines);
  push @metricNames,"Median LOC per File";
  push @metrics,$largeFileCount;
  push @metricNames,"Files > $maxFileSize LOC";
  push @metrics,$largeFunctionCount;
  push @metricNames,"Functions > $maxFunctionSize LOC";
  

  push @metrics,median(@cbos);
  push @metricNames,"Median CBO";
  push @metrics,$cbosOver;
  push @metricNames,"CBO > $maxCBO";
  push @metrics,median(@wmcs);
  push @metricNames,"Median WMC";
  push @metrics,$wmcsOver;
  push @metricNames,"WMC > $maxWMC";
  push @metrics,median(@wcmcyclos);
  push @metricNames,"Median WMC-McCabe";
  push @metrics,$wmccyclosOver;
  push @metricNames,"WMC-McCabe > $maxWMCM";
  push @metrics,median(@rfcs);
  push @metricNames,"Median RFC";
  push @metrics,$rfcsOver;
  push @metricNames,"RFC > $maxRFC";
  
  #Create the html report
  printprogress($report,.98,"Formatting Output");

  #Export the matrix info to the specified html file
  add_progress($report,.01,"Creating HTML Report");
 
  my $infoString;
  $infoString .=  "var nodes=[";
  my @outputStrings;
  foreach my $file (@fileObjList){
    my $string;
    $string .="{\"name\":\"".cleanJSONString($file->{name})."\"";
    $string .=",\"componentM\":\"".cleanJSONString($file->{componentM})."\"";   
    $string .=",\"componentCP\":\"".cleanJSONString($file->{componentCP})."\""  if $file->{componentCP};
    $string .=",\"alphaOrder\":".$file->{id};
    $string .=",\"medianOrder\":".$file->{medianOrder};
    $string .=",\"coreOrder\":".$file->{coreOrder} if  $coreGroup;
    $string .=",\"group\":".$file->{group} if $file->{group};
    $string .="}";
    push @outputStrings, $string;
  }
  $infoString .=   join( ",", @outputStrings );
  $infoString .=   " ];\n";
 
  #dependency links
  $infoString .=   "var links=[";
  @outputStrings=();
  for(my $row = 0; $row < $fileCount; $row++) {
    for(my $col = 0; $col < $fileCount; $col++) {
      if ($designStructureMatrix[$row][$col]){
        push @outputStrings,"{\"source\":$row,\"target\":$col,\"value\":1}";
      }
    }
  }
  $infoString .=   join( ",", @outputStrings );
  $infoString .=     "];\n";
  
  #Directory info
  $infoString .=   "var directories=[";
  @outputStrings=();
  foreach my $dir (sort {$directoryList{$a}{"first"} <=> $directoryList{$b}{"first"};} keys %directoryList){
    push @outputStrings,"{\"dirName\":\"$dir\",\"first\":".$directoryList{$dir}{"first"}.",\"size\":".$directoryList{$dir}{"size"}."}";
  }
  $infoString .=   join( ",", @outputStrings );
  $infoString .=     "];\n";
  
  #Group Sizes
  $infoString .= makeJavaScriptHash(\%mGroupSize,"mGroupSize");
  $infoString .= makeJavaScriptHash(\%cpGroupSize,"cpGroupSize")if  $coreGroup;
  
  my $i=0;
  $infoString .=   "var metrics=[";
  @outputStrings=();
  foreach my $metric(@metrics){
     push @outputStrings,"{\"name\":\"$metricNames[$i]\",\"value\":\"".$metrics[$i]."\",\"order\":".$i."}";
    $i++;
  }
  $infoString .=   join( ",", @outputStrings );
  $infoString .=     "];\n";
  $infoString .= "var version=\"$version\"\n";


  my $fileString = htmlfile();
  $fileString =~ s/<<EXTERNALDATA>>/$infoString/;

  
  my $htmlFile = $outputDir.$slash."index.html";
  open (FILE,'>',$htmlFile) || die ("Couldn't open $htmlFile $!\n");
  print FILE  $fileString ;
  close FILE;
  


  #Create the XML file for adding Architectures
  if ($createArch){
    my %groups;
    foreach my $file (@fileObjList){
      push(@{$groups{Median}{$file->{componentM}}},$file);
      push(@{$groups{Core}{$file->{componentCP}}},$file) if $file->{componentCP};
    }

    #create arch xml file for Median
    my $medianxml;
    $medianxml .= "<!DOCTYPE arch><arch name=\"Median\">\n";
    foreach my $group (keys %{$groups{Median}}){
      $medianxml .= " <arch name=\"$group\">\n";
      foreach my $file (@{$groups{Median}{$group}}){
        $medianxml .= '   c'.$file->{longname}.'@file='.$file->{longname}."\n";
      }
      $medianxml .= " </arch>\n"
    }
    $medianxml .= "</arch>\n";

    $outputFileName = $outputDir.$slash."arch_median.xml";
    open (FILE,'>',$outputFileName) || die ("Couldn't open $outputFileName $!\n");
    print FILE  $medianxml ;
    close FILE;
    
    my $cpxml;
    if  ($coreGroup){
      my $cpxml;
      $cpxml .= "<!DOCTYPE arch><arch name=\"Core-Periphery\">\n";
      foreach my $group (keys %{$groups{Core}}){
        $cpxml .= " <arch name=\"$group\">\n";
        foreach my $file (@{$groups{Core}{$group}}){
          $cpxml .= '   c'.$file->{longname}.'@file='.$file->{longname}."\n";
        }
        $cpxml .= " </arch>\n"
      }
      $cpxml .= "</arch>\n";
      $outputFileName = $outputDir.$slash."arch_core.xml";
      open (FILE,'>',$outputFileName) || die ("Couldn't open $outputFileName $!\n");
      print FILE  $cpxml ;
      close FILE;
    }
    

  }

  printprogress($report,.99,"Report Finished\n");

  #Final Metrics
  my $i=0;
  foreach my $metric(@metrics){
    $report->print($metricNames[$i].": ".commafy($metrics[$i])."\n");
    $i++;
  }
  
  
  my $end_run = time();
  my $run_time = $end_run - $start_run;
  
  $report->print("\n\nReport took $run_time second(s) to run\n");
  $report->print("HTML Report located at $htmlFile\n");
  if ($^O =~ /MSWIN32/i){
    system "start \"\" \"$htmlFile\""; #Extra quotes needed for odd Windows bug
  }
}

#******************** Helper Subroutines  ********************
#show relative progress
sub add_progress{
  my $report = shift;
  my $val = shift;
  my $text = shift;
  $percentComplete += $val;
  printprogress($report,$percentComplete,$text);

}

#Remove special characters from a json string
sub cleanJSONString{
  my $string = shift;
  #escape json special chars
  $string =~ s|\\|\\\\|g; 
  $string =~ s|\/|\\\/|g;
  $string =~ s|"|\\"|g;
  return $string;
}

#Correctly apply commas to numeric strings
sub commafy {
  my $input = shift;
  $input = reverse $input;
  $input =~ s<(\d\d\d)(?=\d)(?!\d*\.)><$1,>g;
  return reverse $input;
}

#Returns the number of external methods/functions called from within this class
sub getCalledMethodCount{
  my $class = shift;
    my $depends = $class->depends;
    my %calledMethods;
    my $called = 0;
    if ($depends){
      my @depRefs = $depends->values();
      foreach my $defref (@depRefs){
        next unless $defref->kind->check("call");
        next unless $defref->ent->kind->check("method, function");
        next if $calledMethods{$defref->ent->id};
        $calledMethods{$defref->ent->id}=1;
        #print "\t".$defref->scope->name."(".$defref->scope->id.") ".$defref->kind->longname()." of ".$defref->ent->name."(".$defref->ent->id.") at line ".$defref->line."\n";
      }
      $called = scalar keys %calledMethods;
    }
    return $called;
}


# return declaration ref (based on language) or 0 if unknown
sub getDeclRef
{
   my ($ent) =@_;
   my @decl=();
   my $language = $ent->language();
   return @decl unless defined ($ent);
   
   if ($language =~ /ada/i)
   {
      my @declOrder = ("declarein ~spec ~body ~instance ~formal ~incomplete ~private ~stub",
                 "spec declarein",
                 "body declarein",
                 "instance declarein",
                 "formal declarein",
                 "incomplete declarein",
                 "private declarein",
                 "stub declarein");
               
      foreach my $type (@declOrder)
      {
         @decl = $ent->refs($type);
         if (@decl) { last;  }
      }
   }
   elsif ($language =~ /fortran/i)
   {
      @decl = $ent->refs("definein");
      if (!@decl) {   @decl = $ent->refs("declarein");  }
   }
   else # C/C++
   {
      @decl = $ent->refs("definein");
      if (!@decl) {   @decl = $ent->refs("declarein"); }
   }
   
   if (@decl)
   {   return $decl[0];   }
   else
   {   return 0;   }
}


#This is the text that gets sent to the html output file, <<EXTERNALDATA>> gets replaced with project specific data
sub htmlfile{

return << 'ENDHTMLDOC'
<!DOCTYPE html>
<script>
<<EXTERNALDATA>>



// **************Everything below this line is template that needs to not have project specific information****************************
</script>
<style>

:root {
  --main-bg-color: #CFE8EF;
  --dark-bg-color: #C6DBF0;
  --extra-dark-bg: #AED1E6;
  --font-color: #3B5863;
  --border: 1px solid #85C7DE;
  color: var(--font-color);
  font-family:arial;
}

#topbox{
  height:auto;
  background-color: var(--main-bg-color);
  border-radius: 10px;
  border: var(--border);
  max-width:960px;
  margin:0px auto;

}

#topbox div{
  text-align:center;
}

#topbox-container {
  width:100%;
  position:fixed;
  top:0px;
  height:auto;
  z-index: 100;
}

input[type=range] {
  -webkit-appearance: none;
  width: 200px;
  background-color: var(--extra-dark-bg);
}

select{
  background-color: var(--extra-dark-bg);
}

select option {
  background-color: var(--extra-dark-bg);
}
#pageTitle{
  text-align:center;
  margin: 5px;
}

.controller{
  display: inline-block;
  text-align: center;
}

button{
  background-color: var(--extra-dark-bg);
  border-radius: 8px;
}
#zoomtag{
  display: inline-block; 
  width:3em;
}


body{
  position:absolute;
  overflow:auto;
}
.graphContainer {
  padding: 10px;
  margin: auto;
  width:100%;
  position:relative;
}

#myCanvas{
  padding-left: 0;
  padding-right: 0;
  margin-left: auto;
  margin-right: auto;
  display: block;
  z-index: 2;
}

.metrics{
  border-radius: 10px;
  width: 170px;
  border: var(--border);
  padding: .5em;
  padding-top:0em;
  background-color: var(--main-bg-color);
  margin: 0 auto;
  position:fixed;
  left:0;
  top:25%;
  z-index: 90;
  line-height:110%
}

.metricsTitle{
  padding:2px;
  margin: 0px;
  text-align: center;
}

.metricName{
  font-weight:bold;
  background-color: var(--dark-bg-color);
  width:100%;
}

.metricVal{
  text-align:right;
}

#hoverInfo{
  height:2.5em;
}

#description{
  max-width:960px;
  margin: auto;
  text-align:center;
  background-color:var(--main-bg-color);
  border:var(--border);
  border-radius: 10px;
  z-index: 80;
  padding:5px;
}


#description-cont {
  width:100%;
  position:fixed;
  bottom: 0;
  left: 0;
  z-index:0;
}



</style>
<html>
<body onload="draw()" onresize="draw()">
<header>
  <div id="topbox-container">
  <div id="topbox">
      <h1 id="pageTitle" style="">Directory Structure Based Design Structure Matrix</h1>
      <span class=controller style="width:35%"><b>Select Matrix</b> 
        <select id="order" onchange="draw(this.value)">
          <option value="Architect" selected>Architect's View</option>
          <option value="Median">Median Matrix</option>
        </select>
      </span>
      <span class=controller style="width:14%"><button id=metricsbtn onclick="metricsBtnPress()">Hide Metrics</button></span>
      <span class=controller style="width:14%"><button id=descbtn onclick="descBtnPress()">Hide Description</button></span>
      <span class=controller style="width:35%">Zoom:<input name="zoom" type="range" name="points" min="0" max="10"  value="1" oninput="setZoom(this.value)" onchange="setZoom(this.value)" onmouseup="draw()">
        <span id="zoomtag">1X</span>
      </span>
      
      <div id="hoverInfo"></div>
    </div>
  </div>
</header>
<span class="metrics" id="metricspane"></span>


    <div class="graphContainer" id="graphContainer">
    <canvas id="myCanvas" ></canvas>
    </div>
</body>

<footer>
  <div id ="description-cont">
        <div  id="description"></div>
</footer>
<script charset="utf-8">


// Add the Metrics Section
var projName;
var isCorePeriphery =false;
var MetricsHTML = "<h3 class=\"metricsTitle\">Metrics</h3>";
metrics.forEach(function(metricObj){
  if (metricObj["name"] == "Project Name"){
    projName = metrics[0].value;
    return;
    }
  //Add the Core-Periphery graph if it exists.
  if (metricObj["name"] == "Architecture Type" && (metricObj["value"] == "Core-Periphery" || metricObj["value"] == "Borderline Core-Periphery")){
    var x = document.getElementById("order");
    var option = document.createElement("option");
    option.text = "Core-Periphery Matrix";
    option.value ="Core-Periphery";
    isCorePeriphery=true;
    x.add(option);
  }
  var value = metricObj["value"];
  if(!isNaN(value)){
    value=+value;
    value = value.toLocaleString();
  }
  MetricsHTML += "<div class=\"metricName\">"+metricObj["name"]+"</div> <div class=\"metricVal\"> "+ value +"</div>\n";
});
document.getElementById("metricspane").innerHTML =   MetricsHTML;

//Setup ordered node lists for the non-architect views
var medianNodes =[];
var coreNodes = [];
nodes.forEach(function(node){
  medianNodes[node.medianOrder]=node;
  if (isCorePeriphery){
    coreNodes[node.coreOrder]=node;
  }
});

// Setup Global information
var groupOrder = ["Shared","Core","Peripheral","Control","Isolate"];
var nodeColors = {Shared: "#69ad67",Core: "#ea6a66",Peripheral: "#ebebeb",Control: "#ebed62",Isolate: "#eabe62"};
var medianNames ={Shared:"Shared-M",Core:"Central",Peripheral:"Periphery-M",Control:"Control-M",Isolate: "Isolate"};
var baseColor = "#1a12f0";
var backgroundColor = "lightgray";
var gridColor = 'rgba(255,255,255,.5)';//"white";
var outlineColor = 'rgba(0,0,0,.5)';//"black";
var minBorderLineWidth = .5; //Minimum thickness for border lines
var nodeLineWidth;


var CurGraph="Architect";
var scaleRatio;
var canvas = document.getElementById("myCanvas");
var ctx = canvas.getContext("2d");

var zoomLevel=1;
var initFontSize=12;
var numFiles=nodes.length;
var canvasOffset = 0;
var showMetrics=1;
var showDescription=1;
  

  
function draw(graph){
  if (typeof graph != 'undefined'){
    CurGraph=graph;
  }
  
  //Get get Document size info so the image will fit in the current window.
  var bkgWidth = window.innerWidth || document.body.clientWidth;
  var bkgHeight = window.innerHeight || document.body.clientHeight;
  var headerSpace = document.getElementById('topbox-container').offsetHeight;
  var footerSpace = 0;
  if (showDescription){
   footerSpace = 85;
  }
  var metricSpace = 0;
  if (showMetrics){
    metricSpace =   document.getElementById("metricspane").offsetWidth;
  }
  
  var defaultBkgSize = bkgHeight - headerSpace - footerSpace-50;
  //if (defaultBkgSize > 1000)
   // defaultBkgSize = 1000;
  var bkgSize = defaultBkgSize*zoomLevel;
  canvas.width=bkgSize;
  canvas.height=bkgSize;
  document.getElementById("graphContainer").style.height=bkgSize+"px";
  document.getElementById("graphContainer").style.top=headerSpace+"px";
  document.getElementById("graphContainer").style.left=metricSpace+"px";
  document.getElementById("graphContainer").style.marginBottom=footerSpace+"px";
  //ctx.clearRect(0, 0, bkgSize, bkgSize); //clear canvas for redraw
  
  
  //get the size of the largest number label to calculate the offset
  canvasOffset=0;
  var gridLines = getGridLines();
  if (numFiles > 10){
    gridLines.forEach(function(gridNum){
      ctx.font = (initFontSize*zoomLevel)+"px Arial";
      var txtSize = ctx.measureText(gridNum.toLocaleString()).width;
      canvasOffset=Math.max(txtSize,canvasOffset);
    });
  }

  
  //prepare the canvas the graph goes on
  var size = (bkgSize-canvasOffset)
  scaleRatio = size/numFiles;
  
  //calculate line widths
  var borderLineWidth= minBorderLineWidth;
  if (scaleRatio > 1){
    borderLineWidth = minBorderLineWidth*scaleRatio;
    borderLineWidth = Math.min(borderLineWidth,10)
  }
  nodeLineWidth = scaleRatio*.1;

  if (numFiles > 10){
    //Grid Numbers left side
    gridLines.forEach(function(gridNum){
      ctx.textAlign = "right";
      ctx.font = initFontSize*zoomLevel+"px Arial";
      ctx.fillStyle = outlineColor;
      ctx.textBaseline="middle"; 
      ctx.fillText(gridNum.toLocaleString(),canvasOffset,gridNum*scaleRatio+canvasOffset+scaleRatio/2);
    });
    
      //Grid Numbers top
      ctx.save();
      ctx.translate(canvasOffset,canvasOffset);
      ctx.rotate(-Math.PI/2);
      gridLines.forEach(function(gridNum){
        if (gridNum>0){ //We don't want the zero on both axes
          ctx.textAlign = "left";
          ctx.font = (initFontSize*zoomLevel)+"px Arial";
          ctx.fillStyle = outlineColor;
          ctx.textBaseline="middle"; 
          ctx.fillText(gridNum.toLocaleString(),0,gridNum*scaleRatio+scaleRatio/2);
        }
      });
      ctx.restore();
    
    //Move into the inner part of the canvas now for everything else
    ctx.save();
    ctx.translate(canvasOffset,canvasOffset);
  }
  
  ctx.fillStyle = backgroundColor;
  ctx.fillRect(0,0,size,size)

  
    if (CurGraph == "Core-Periphery"){
    //Core-Periphery background
    var currentXY=0;
    groupOrder.forEach(function(group){
      if (cpGroupSize[group]){
        ctx.strokeStyle = nodeColors[group];
        ctx.fillStyle = nodeColors[group];
        ctx.lineWidth=borderLineWidth;
        roundRect(ctx,currentXY*scaleRatio,currentXY*scaleRatio,cpGroupSize[group]*scaleRatio,cpGroupSize[group]*scaleRatio,0,true);
        currentXY=currentXY+Number(cpGroupSize[group]);
      }
    });
    //Core-Periphery node
    links.forEach(function(link) {
      ctx.strokeStyle = getNodeColor(nodes[link.target],nodes[link.source],"core");
      ctx.fillStyle = baseColor;
      ctx.lineWidth=nodeLineWidth;
      roundRect(ctx,nodes[link.target].coreOrder*scaleRatio,nodes[link.source].coreOrder*scaleRatio,scaleRatio,scaleRatio,.1,true);
    });
    
    //Core-Periphery border
    var currentXY=0;
    groupOrder.forEach(function(group){
      if (cpGroupSize[group]){
        ctx.strokeStyle = outlineColor;
        ctx.lineWidth=borderLineWidth;
        roundRect(ctx,currentXY*scaleRatio,currentXY*scaleRatio,cpGroupSize[group]*scaleRatio,cpGroupSize[group]*scaleRatio,0,false);
        currentXY=currentXY+Number(cpGroupSize[group]);
      }
    });
    
    //Core-Periphery explanatory text
    document.title=projName+" Core-Periphery Based DSM";
    document.getElementById("pageTitle").innerHTML = projName+" Core-Periphery Based Design Structure Matrix";
    document.getElementById("description").innerHTML = 
    "This project contains a Core group of files in red that much of the system is connected with. The other components are organized based on their relationship with the Core group. "+
    "Each point in the matrix represents a directional dependency relationship between two files. Dependencies above the diagonal are cyclic interdependencies which cannot be reduced."+" (v"+version+")";  
  }
  else if (CurGraph == "Median"){
    //Median Background
    var currentXY=0;
    groupOrder.forEach(function(group){
      if (mGroupSize[group]){
        ctx.strokeStyle = nodeColors[group];
        ctx.fillStyle = nodeColors[group];
        ctx.lineWidth=borderLineWidth;
        roundRect(ctx,currentXY*scaleRatio,currentXY*scaleRatio,mGroupSize[group]*scaleRatio,mGroupSize[group]*scaleRatio,.0,true);
        currentXY=currentXY+Number(mGroupSize[group]);
      }
    });
    
    //Median nodes
    links.forEach(function(link) {
      ctx.fillStyle = baseColor;
      ctx.strokeStyle = getNodeColor(nodes[link.target],nodes[link.source],"median");
      ctx.lineWidth=nodeLineWidth;
      roundRect(ctx,nodes[link.target].medianOrder*scaleRatio,nodes[link.source].medianOrder*scaleRatio,scaleRatio,scaleRatio,.1,true,true);
    });
    
    //Median border
    ctx.lineWidth=borderLineWidth;
    var currentXY=0;
    
    groupOrder.forEach(function(group){
      if (mGroupSize[group]){
        ctx.strokeStyle = outlineColor;
        ctx.lineWidth=borderLineWidth;
        roundRect(ctx,currentXY*scaleRatio,currentXY*scaleRatio,mGroupSize[group]*scaleRatio,mGroupSize[group]*scaleRatio,0,false);
        currentXY=currentXY+Number(mGroupSize[group]);
      }
    });
   
    //Median explanatory text
    document.title=projName+" Median Based DSM";
    document.getElementById("pageTitle").innerHTML = projName+" Median Based Design Structure Matrix";
    document.getElementById("description").innerHTML = 
    "This view places all of the significant cyclic groups together in the red Central component. Components are classified based on the median values of the number of direct and indirect connections. "+
    "Each point in the matrix represents a directional dependency relationship between two files. Dependencies above the diagonal are cyclic interdependencies which cannot be reduced"+" (v"+version+")";

  }
  else{ //Architect View
    //Architect View nodes
    
    links.forEach(function(link) {
        ctx.fillStyle = baseColor;
        ctx.strokeStyle = backgroundColor;
        ctx.lineWidth=nodeLineWidth;
        roundRect(ctx,link.target*scaleRatio,link.source*scaleRatio,scaleRatio,scaleRatio,.1,true,true);
      });
    //Architect View Border
    if (Object.keys(directories).length >1){
      directories.forEach(function(dir){
        ctx.strokeStyle = outlineColor;
        ctx.lineWidth=borderLineWidth;
        roundRect(ctx,dir.first*scaleRatio,dir.first*scaleRatio,dir.size*scaleRatio,dir.size*scaleRatio,0,false);
      });
    }
    
    //Architect View explanatory text
    document.title=projName+" Architect's View DSM";
    document.getElementById("pageTitle").innerHTML = projName+" Architect's View Design Structure Matrix";
    document.getElementById("description").innerHTML = 
    "This is the initial design view. Files are shown organized according to their directory structure, or how the System Architect designed it. "+
    "If file i depends on file j, a mark is placed in the row of i and the column of j"+" (v"+version+")";
  }
  
  if(numFiles > 10){
    //Generate the grid lines
  gridLines.forEach(function(gridNum){
      if (gridNum >0){
        ctx.strokeStyle = gridColor;
        ctx.lineWidth=borderLineWidth;
        ctx.beginPath();
        ctx.moveTo(0,gridNum*scaleRatio)
        ctx.lineTo(size,gridNum*scaleRatio);
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(gridNum*scaleRatio,0)
        ctx.lineTo(gridNum*scaleRatio,size);
        ctx.stroke();
      }
    });
  }
    
  //Draw an orgin line
  ctx.strokeStyle = outlineColor;
  ctx.lineWidth= borderLineWidth;
  ctx.beginPath();
  ctx.moveTo(0,0);
  ctx.lineTo(size,size);
  ctx.stroke();
  
 
}


function metricsBtnPress(){
  if (showMetrics ==1){
    showMetrics = 0;
    document.getElementById("metricspane").style.display= "none";
    document.getElementById("metricsbtn").innerHTML= "Show Metrics";
    draw();
  }else{
    showMetrics = 1;
    document.getElementById("metricspane").style.display= "block";
    document.getElementById("metricsbtn").innerHTML= "Hide Metrics";
    draw();
  }
}

function descBtnPress(){
  if (showDescription ==1){
    showDescription = 0;
    document.getElementById("description-cont").style.display= "none";
    document.getElementById("descbtn").innerHTML= "Show Description";
    draw();
  }else{
    showDescription = 1;
    document.getElementById("description-cont").style.display= "block";
    document.getElementById("descbtn").innerHTML= "Hide Description";
    draw();
  }
}

function getGridLines(){
  if (numFiles <= 10){return;}
  var numString = numFiles.toString();
  var strLength = numString.length-1;
  var retNumbers = [];
  var first = parseInt(numString[0]);
 
  for (i = 0;i<= first;i++){
      var tmpNum = (i*Math.pow(10,strLength));
      retNumbers.push(tmpNum);
     
    if (first <= 5){ 
      var tmpNum = (i*10+5) *Math.pow(10,strLength-1)
      if (tmpNum < numFiles){
        retNumbers.push(tmpNum);
      }
    }
  }
  return retNumbers;
}

canvas.addEventListener('mousemove', handleMouseMove, false);
function handleMouseMove(evt){
    var rect = canvas.getBoundingClientRect();
    var absX = evt.clientX - rect.left;
    var absY = evt.clientY - rect.top;
    var mouseX= Math.floor((absX-canvasOffset) / scaleRatio);//  Math.floor((evt.clientX-rect.left-canvasOffset)/(rect.right-rect.left-canvasOffset)*canvas.width/scaleRatio);
    var mouseY= Math.floor((absY-canvasOffset) / scaleRatio);//Math.floor((evt.clientY-rect.top-canvasOffset)/(rect.bottom-rect.top-canvasOffset)*canvas.height/scaleRatio);
    var message="";
    var title = "";
    var currentXY=0;
    var size;
    var selectedGroup;
  
  
  if (CurGraph == "Core-Periphery"){
    groupOrder.forEach(function(group){
      var groupSize = Number(cpGroupSize[group]);
      if (!groupSize){
        return;
      }
      if (mouseX>=currentXY && mouseX<=currentXY+groupSize && mouseY>=currentXY && mouseY<=currentXY+groupSize){
        selectedGroup=group;
        size=groupSize;
      }
      switch(selectedGroup){
        case("Shared"):
          message="<span style=\"color:"+baseColor+"\">Shared components("+size+" Files)  These files are used by many other components, both in and out of the Core.</span>";
          title= "Shared components("+size+" Files)";
          break;
        case("Core"):
          message="<span style=\"color:"+baseColor+"\">Core components("+size+" Files)  Core components. A substantial part of the system is linked to these files.</span>";
          title= "Core components("+size+" Files)";
          break;
        case("Peripheral"):
          message="<span style=\"color:"+baseColor+"\">Peripheral components("+size+" Files)  These files do not interact with the Core</span>";
          title= "Peripheral components("+size+" Files)";
          break;
        case("Control"):
          message="<span style=\"color:"+baseColor+"\">Control components("+size+" Files)  These files make use of other components but are not used by other components</span>";
          title= "Control components("+size+" Files)";
          break;
        case("Isolate"):
          message="<span style=\"color:"+baseColor+"\">Isolated components("+size+" Files)  These files are not connected to any other components.</span>";
          title= "Isolated components("+size+" Files)";
          break;
      }
      currentXY=currentXY+groupSize;
    });
    message =message+"<br>"+coreNodes[mouseY].name+" &rarr;  "+coreNodes[mouseX].name;
  }
  else if (CurGraph == "Median"){
    groupOrder.forEach(function(group){
      var groupSize = Number(mGroupSize[group]);
      if (!groupSize){
        return;
      }
      if (mouseX>=currentXY && mouseX<=currentXY+groupSize && mouseY>=currentXY && mouseY<=currentXY+groupSize){
        selectedGroup=medianNames[group];
        size=groupSize;
      }
     switch(selectedGroup){
      case("Shared-M"):
        message="<span style=\"color:"+baseColor+"\">Shared-M components("+size+" Files) These files are used by many other components, including the Central Components</span>";
        title= "Shared-M components("+size+" Files)";
        break;
      case("Central"):
        message="<span style=\"color:"+baseColor+"\">Central components("+size+" Files)  These files are the main cyclic groups in the program that many other components interact with</span>";
        title= "Central components("+size+" Files)";
        break;
      case("Periphery-M"):
        message="<span style=\"color:"+baseColor+"\">Periphery-M components("+size+" Files)  These files do not interact with the Central components</span>";
        title= "Periphery-M components("+size+" Files)";
        break;
      case("Control-M"):
        message="<span style=\"color:"+baseColor+"\">Control-M components("+size+" Files)  These make use of other components but are not used by other components</span>";
        title= "Control-M components("+size+" Files)";
        break;
      case("Isolate"):
        message="<span style=\"color:"+baseColor+"\">Isolated components("+size+" Files)  These files are not connected to any other components.</span>";
        title= "Isolated components("+size+" Files)";
        break;
    }
    
      currentXY=currentXY+groupSize;
    });
    message =message+"<br>"+medianNodes[mouseY].name+" &rarr;  "+medianNodes[mouseX].name;
  }
  else{ //Architect View
    directories.forEach(function(dir){
      if (mouseX>=currentXY && mouseX<=currentXY+dir.size && mouseY>=currentXY && mouseY<=currentXY+dir.size){
        message="<span style=\"color:"+baseColor+"\">Directory: '"+dir.dirName+" ("+dir.size+" Files)</span>";
        title = dir.dirName+" ("+dir.size+" Files)";
      }
      currentXY=currentXY+dir.size;
    });
    message =message+"<br>"+nodes[mouseY].name+" &rarr;  "+nodes[mouseX].name;
  
  }
  
  canvas.title=title;
  document.getElementById("hoverInfo").innerHTML = message;
}

function setZoom(newZoom){
  if (newZoom == 0){
    newZoom = "1/2";
    zoomLevel=.5;
  }else{
    zoomLevel=newZoom;
  }
  document.getElementById("zoomtag").innerHTML = newZoom+"X";
  //draw();
}
/**
 * Draws a rounded rectangle using the current state of the canvas.
 * If you omit the last three params, it will draw a rectangle
 * outline with a 5 pixel border radius
 * @param {CanvasRenderingContext2D} ctx
 * @param {Number} x The top left x coordinate
 * @param {Number} y The top left y coordinate
 * @param {Number} width The width of the rectangle
 * @param {Number} height The height of the rectangle
 * @param {Number} radius What percent of the rectangle should curve (in decimal)
 * @param {Boolean} [fill = false] Whether to fill the rectangle.
 * @param {Boolean} [stroke = true] Whether to stroke the rectangle.
 */
function roundRect(ctx, x, y, width, height, radius, fill, stroke) {
  if (typeof stroke == 'undefined') {
    stroke = true;
  }
  if (typeof radius === 'undefined') {
    radius = .1;
  }
  if (width < .1 || height < .1){
    ctx.fillRect(x,y,width,height);
  }else{
    radius = radius * width;
    ctx.beginPath();
    ctx.moveTo(x + radius, y);
    ctx.lineTo(x + width - radius, y);
    ctx.quadraticCurveTo(x + width, y, x + width, y + radius);
    ctx.lineTo(x + width, y + height - radius);
    ctx.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
    ctx.lineTo(x + radius, y + height);
    ctx.quadraticCurveTo(x, y + height, x, y + height - radius);
    ctx.lineTo(x, y + radius);
    ctx.quadraticCurveTo(x, y, x + radius, y);
    ctx.closePath();
    if (fill) {
      ctx.fill();
    }
    if (stroke) {
      ctx.stroke();
    }
  }

}

 function getNodeColor(node1,node2,type){
    var comp1,comp2;
    var color =  backgroundColor;
    if (type == "core"){
      comp1 = node1.componentCP;
      comp2 = node2.componentCP;
    }else{
      comp1 = node1.componentM;
      comp2 = node2.componentM;
    }
    if (comp1 == comp2){
      color = nodeColors[comp1];
    }
    return color;
  }
</script>




ENDHTMLDOC
}

#This creates the script options
sub init {
  my $report = shift;
  $abort_called=0; #reset the cancel flag in case it was set on another run
  $report->option->directory("outputDir","Specify output directory","");
  $report->option->integer("MaxFileSize","Maximum Recommended File Size (LOC)",200);
  $report->option->integer("MaxFuncSize","Maximum Recommended Function Size (LOC)",200);
  $report->option->integer("MaxCBO",     "Maximum Recommended Coupling Between Object Classes (CBO)",8);
  $report->option->integer("MaxWMC",     "Maximum Recommended Weighted Methods per Class(WMC)",12);
  $report->option->integer("MaxWMCM",    "Maximum Recommended Weighted Methods per Class with McCabe(WMC-McCabe)",100);
  $report->option->integer("MaxRFC",     "Maximum Recommended Response for Class(RFC)",30);
  $report->option->checkbox("createTestFiles","Generate validation files for testing",0);
  $report->option->checkbox("createArch",     "Generate Architecture import files",1);
  $report->option->checkbox("createMetrics",  "Generate metrics csv files",1);
  }

#return the longest item from a list
sub longestItem {
    my $max = -1;
    my $max_ref;
    for (@_) {
        if (length > $max) {  # no temp variable, length() twice is faster
            $max = length;
            $max_ref = \$_;   # avoid any copying
        }
    }
    $$max_ref
}

# Turn a hash into the text for a javascript hash
sub makeJavaScriptHash(){
  my $hashVal = shift;
  my $name = shift;
  
  my @outputStrings=();
  my $infoString = "var $name={";
  foreach (sort keys %{$hashVal}){
    push @outputStrings, "$_:\"$hashVal->{$_}\"";
  }
  $infoString .=   join( ",", @outputStrings );
  $infoString .= "};\n";
  return $infoString;

}

#Return the median value of an array
sub median{
    my @vals = sort {$a <=> $b} @_;
    my $len = @vals;
    if($len%2) #odd?
    {
        return $vals[int($len/2)];
    }
    else #even
    {
        return ($vals[int($len/2)-1] + $vals[int($len/2)])/2;
    }
}


# Print a Square Matrix to the specific text file
sub printSquareMatrix{
  my $firstColumnListRef = shift;  #ref to a list of titles to be printed before the matrix
  my $matrixRef = shift; #ref to the matrix that will be printed
  my $fileName = shift; #if specified send the output to the file - recommended
  
  my @firstColumnList = @{$firstColumnListRef};
  my $length = length longestItem(@firstColumnList);
  
  if ($fileName){
    open (FILE,'>',"$fileName") || die ("Couldn't open $fileName $!\n");
  }
  my @matrix = @{$matrixRef};
  for(my $row = 0; $row < scalar @firstColumnList; $row++) {
    my $printString = sprintf("%${length}s ", $firstColumnList[$row]);
    for(my $col = 0; $col < scalar @firstColumnList; $col++) {
      my $val = "0";
      $val = 1 if $matrix[$row][$col];
      $printString.="$val";
    }
    print FILE $printString."\n" if $fileName;
    print $printString."\n" unless $fileName;
  }
  close FILE if $fileName;
}

#Ouput the progress
sub printprogress{
  my $report = shift;
  my $percent = shift;
  my $text = shift;
  $percentComplete = $percent;
  my $printPercent = sprintf("%.0f",$percent*100);
  $report->progress($printPercent,"$printPercent% - $text");
}

#Sort the Core Periphery group using the specicied criteria
sub sortByCorePeriphery{
  if ($a->{componentCP} ne $b->{componentCP}){
    if ($a->{componentCP} eq "Shared"){return -1}
    if ($b->{componentCP} eq "Shared"){return 1}
    if ($a->{componentCP} eq "Core"){return -1}
    if ($b->{componentCP} eq "Core"){return 1}
    if ($a->{componentCP} eq "Peripheral"){return -1}
    if ($b->{componentCP} eq "Peripheral"){return 1}
    if ($a->{componentCP} eq "Control"){return -1}
    if ($b->{componentCP} eq "Control"){return 1}
    #Should not get here since both would have to be  "isolate"
  }
  if ($a->{componentCP} eq $b->{componentCP}){
  # Same components, sort by VFI Desc then VFO asc
  return $b->{vfi} <=> $a->{vfi} || $a->{vfo} <=> $b->{vfo}
  }
}

#Sort the Median goup using the specicied criteria
sub sortByMedian{
  if ($a->{componentM} ne $b->{componentM}){
    if ($a->{componentM} eq "Shared"){return -1}
    if ($b->{componentM} eq "Shared"){return 1}
    if ($a->{componentM} eq "Core"){return -1}
    if ($b->{componentM} eq "Core"){return 1}
    if ($a->{componentM} eq "Peripheral"){return -1}
    if ($b->{componentM} eq "Peripheral"){return 1}
    if ($a->{componentM} eq "Control"){return -1}
    if ($b->{componentM} eq "Control"){return 1}
    #Should not get here since both would have to be  "isolate"
  }
  if ($a->{componentM} eq $b->{componentM}){
  # Same components, sort by VFI Desc then VFO asc
  return $b->{vfi} <=> $a->{vfi} || $a->{vfo} <=> $b->{vfo}
  }
}

#Recursivly go through the dependency tree for the given node and add its indirect dependencies
#Makes use of Tarjan's strongly connected components algorithm to handle cycles
sub strongconnect(){
  my $report=shift;
  my $v = shift;
  $v->{index}=$index;
  $v->{lowlink}=$index;
  $index++;
  push @stack, $v;
  $v->{onstack}=1;
 
  my @deps = ($v->{entid});
  #Consider successors of v
  foreach my $wID (@{$v->{depends}}){
    return if $abort_called;
    Understand::Gui::yield();
    my $w = $fileObjsByEntID{$wID};
    if($w->{index}){
      push @deps, @{$w->{indirect}};
    }
    if(! $w->{index}){
      # Successor w has not yet been visited; recurse on it
      push @deps, strongconnect($report,$w);
      $v->{lowlink} = min ($v->{lowlink}, $w->{lowlink});
    }elsif ($w->{onstack}){
      #Successor w is in stack S and hence in the current SCC
      $v->{lowlink} = min ($v->{lowlink}, $w->{index});
    }
  }
  
  
  my @strongGraph;
  my $w;
  #If v is a root node, pop the stack and everything on it is strongly connected
  if ($v->{lowlink} == $v->{index}){
    do{
      $w = pop @stack;
      $w->{onstack}=0;
      push @strongGraph, $w;
      push @deps, $w->{entid};
      foreach (@{$w->{depends}}){
        push @deps, $_;
      }
    }while ($w->{id} != $v->{id});
   
  }
   my %depHash;
    foreach (@deps){
      $depHash{$_}=1 if $_;
    }
    @deps = keys %depHash; 
    foreach my $dep (@deps){
      push @strongGraph, $v unless @strongGraph;
      foreach $w (@strongGraph){
        $visibilityMatrix[$w->{id}][$fileObjsByEntID{$dep}->{id}] = 1;
        push @{$w->{indirect}},$dep;
      }
    }
    $analyzedCount++;
    add_progress($report,(.7*10/$fileCount),"Calculating Transitive Closure") unless $analyzedCount%10;
    return @deps;
}


#********************* Conversion Functions *********************

sub openDatabase($)
{
    my ($dbPath) = @_;

    my $db = Understand::Gui::db();

    # path not allowed if opened by understand
    if ($db&&$dbPath) {
  die "database already opened by GUI, don't use -db option\n";
    }

    # open database if not already open
    if (!$db) {
  my $status;
  print usage("Error, database not specified\n\n") && exit() unless ($dbPath);
  ($db,$status)=Understand::open($dbPath);
  die "Error opening database: ",$status,"\n" if $status;
    }
    return($db);
}

sub closeDatabase($)
{
    my ($db)=@_;

    # close database only if we opened it
    $db->close() if $dbPath;
}

sub usage($) {
    my $string =  shift(@_) . <<"END_USAGE";
Usage: $0 -db database
  -db database  Specify Understand database (required for uperl, inherited from Understand)
END_USAGE
  foreach my $opt (keys %{$report->option()} ){
    next if $opt eq "db";
    $string .= "  -$opt";
    $string .= " ".$report->option->{$opt}{kind} if $report->option->{$opt}{kind} ne "boolean";
    $string .= "    ".$report->option->{$opt}{desc}."\n";
    my $choices = $report->option->{$opt}{choices};
    $string .= "        Valid Options: ".join(',',@$choices)." \n" if $choices;
    $string .= "        Defaults To : ".$report->option->{$opt}{default}."\n" if $report->option->{$opt}{default};
  }
  print $string;
}

sub setupOptions(){
  my @optList;
  push @optList,"db=s";
  push @optList,"help";
  foreach my $opt (keys %{$report->option()}){
    my $string = $opt;
    $opt .= "=s" if $report->option->{$opt}{kind} ne "boolean";
    push @optList,$opt;
  }
  GetOptions(\%options,@optList);
  $dbPath = $options{db};
  $help = $options{help};
  foreach my $opt (keys %options){
    next if $opt eq "db";
    next if $opt eq "help";
    $report->option->set($opt,$options{$opt});
  }
  # help message
  print usage("") && exit () if ($help);
  # open the database
  my $db=openDatabase($dbPath);
  $report->db($db);
}

#*******************************Packages**********************************************
package convertIreport;
use strict;

sub new {
   my($class) = @_;
   my $self = bless({}, $class);
    return $self;
  }

# Return the database associated with the report.
sub db {
    my $report = shift;
    my $db = shift;
    $report->{db}=$db if $db;
    return $report->{db};
}
sub bgcolor {}
sub bold {}
sub entity {}
sub fontbgcolor {}
sub fontcolor {}
sub hover {}
sub italic {}
sub nobold {}
sub noitalic {}
sub print {
    my $report = shift;
    my $text = shift;
    my $treeDepth = $report->{depth};
    my $prestring;
    my $poststring;
    if ($treeDepth){
      $prestring = "|"x($treeDepth-1);
      $poststring="\n";
    }
    print $prestring.$text.$poststring;
}
sub progress {}
sub syncfile {}
sub tree {
    my $report = shift;
    my $depth = shift;
    my $expand = shift;
    $report->{depth}=$depth;
}
sub option {
    my $report = shift;
    if (! $report->{opt}){
      $report->{opt} =  convertOption->new($report);
    }
    return $report->{opt};
}

1;
package convertOption;
use strict;

# Class or object method. Return a new report object.
sub new {
   my($class, $db) = @_;
   my $self = bless({}, $class);
   $self->{db} = $db;
    return $self;
}


sub checkbox       {
  my ($self, $name, $desc )=@_;
  $self->{$name} = { 
    desc => $desc,
    variable => "opt_$name",
    kind  => "boolean",
  };
}

sub checkbox_horiz {choice(@_);}
sub checkbox_vert  {choice(@_);}
sub choice{
  my ($self, $name, $desc, $choices, $default )=@_;
  $self->{$name} = { 
    desc => $desc,
    variable => "opt_$name",
    kind  => "choice",
    choices => $choices,
    default => $default,
    setting => $default,
  };
}
sub directory      { text(@_,"directory");}
sub file           { text(@_,"file");}
sub integer        { text(@_,"integer");}
sub label          { text(@_,"label");}
sub lookup         {
  my ($self, $name ) = @_;
  return $self->{$name}{setting};
}
sub radio_horiz    {choice(@_);}
sub radio_vert     {choice(@_);}
sub set{
  my ($self, $name, $value) = @_;
  $self->{$name}{setting} = $value;
}
sub text{
  my ($self, $name, $desc,$default, $kind) = @_;
  $kind = "text" unless $kind;
  $self->{$name} = { 
    desc => $desc,
    variable => "opt_$name",
    kind  => $kind,
    default => $default,
    setting => $default,
  };
}

1;
#*******************************Core Packages**********************************************
package fileObj;
sub new{
  my $class = shift;
  my $id = shift;
  my $ent = shift;
  my $self = {
    analyzed => 0,
    class => '',
    depends=>[],
    entid => $ent->id(),
    id => $id,
    indirect => [],
    longname => $ent->longname(1),
    name => $ent->name(),
    relname => $ent->relname(),
    vfi => 0,
    vfo => 0,
    group => '',
    maxRFC => '',
    maxCBO => '',
    maxWMC => '',
    maxWMCM=> '',
    LOC=> '',
    commentToCode => '',
    componentM => '',
    componentCP => ''
    
  };
   bless($self, $class);
   return($self);
}

sub vfiInc {
    my $self = shift;
    $self->{vfi} = $self->{vfi}+1;
}

sub vfoInc {
    my $self = shift;
    $self->{vfo} = $self->{vfo}+1;
}

1;
