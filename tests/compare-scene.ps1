param(
  [string]$Reference = '86e1636',
  [string[]]$Sizes = @('390,844','1024,768','1920,1080'),
  [switch]$Quick,
  [switch]$Profile,
  [switch]$HardwareAcceleration,
  [switch]$VisualOnly,
  [double]$DeviceScaleFactor = 1,
  [string]$Browser = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$temp = Join-Path ([IO.Path]::GetTempPath()) ('nrg-compare-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
$before = (git -C $root show "${Reference}:energy-3d-scene.html") -join "`n"
if ($LASTEXITCODE) { throw 'Cannot load the reference scene from Git.' }
$after = [IO.File]::ReadAllText((Join-Path $root 'energy-3d-scene.html'))
$scripts = @()
foreach ($source in @($before,$after)) {
  $script = [regex]::Match($source,'<script>(.*?)</script>','Singleline').Groups[1].Value
  $script = $script.Replace('document.getElementById("scene")','makeCanvas()')
  $script = [regex]::Replace($script,'      var target=0,raf=0[^;]*;.*?resize\(\);update\(\);', @'
      var target=0,raf=0;
      scenes.push({
        canvas:canvas,
        render:function(progress){var begin=realNow();scrollProgress=progress;draw();return realNow()-begin;},
        resize:resize,
        profile:function(progress){
          var stats={};
          function wrap(name,fn){return function(){var begin=realNow();try{return fn.apply(this,arguments);}finally{var entry=stats[name]||(stats[name]={ms:0,calls:0});entry.ms+=realNow()-begin;entry.calls++;}};}
          PROFILE_SETUP
          scrollProgress=progress;draw();
          PROFILE_RESTORE
          return stats;
        },
        info:function(){return {buildings:streetscape.length,faces:streetscape.reduce((n,b)=>n+b.faces.length,0),windows:streetscape.reduce((n,b)=>n+b.faces.reduce((m,f)=>m+f.windows.length,0),0),panels:finalFactory.detailPanels.length,paths:finalFactory.detailPaths.length,hydroPaths:hydroPaths.length};}
      });
'@, 'Singleline')
  $setupProfile = @()
  $restoreProfile = @()
  foreach ($name in @('drawBackground','drawStreetscape','prepareDepth','rasterTriangle','maskArchitecture','fillPolygon3D','fillSurface3D','strokePath3D','strokePaths3D','buildStrokeTrace','drawInnerCurrent','drawHydroScene','drawWindField','drawFactoryDetails')) {
    $setupProfile += "var original_$name=$name;$name=wrap('$name',$name);"
    $restoreProfile += "$name=original_$name;"
  }
  $script = $script.Replace('PROFILE_SETUP',($setupProfile -join "`n")).Replace('PROFILE_RESTORE',($restoreProfile -join "`n"))
  $scripts += $script
}
$setup = @'
var scenes=[],simulationTime=1000,realNow=performance.now.bind(performance),viewport=location.hash.slice(1).split(',').map(Number),accelerated=HARDWARE_ACCELERATION;
performance.now=function(){return simulationTime;};
function makeCanvas(){var canvas=document.createElement('canvas');canvas.style.width=viewport[0]+'px';canvas.style.height=viewport[1]+'px';document.body.appendChild(canvas);return canvas;}
window.onerror=function(message){document.documentElement.setAttribute('data-error',message);};
'@
$checks = @'
var results=[],captures=[],timings=[];
function check(pass,name){results.push({pass:!!pass,name:name});}
// Canvas raster work can be deferred. Read one pixel so each measured frame includes completion.
function finish(scene){scene.canvas.getContext('2d').getImageData(0,0,1,1);}
try{
  scenes.forEach(s=>s.resize());
  check(JSON.stringify(scenes[0].info())===JSON.stringify(scenes[1].info()),'Identical counts of buildings, faces, windows, equipment and hydro paths');
  var positions=[0,.025,.12,.24,.31,.35,.43,.5,.58,.67,.78,.9,1,.58,.12];
  positions.forEach(function(progress,index){
    for(var settle=0;settle<2;settle++){
      simulationTime=10000+index*4000+settle*800;
      scenes.forEach(s=>s.render(progress));
    }
    var a=scenes[0].canvas.getContext('2d').getImageData(0,0,scenes[0].canvas.width,scenes[0].canvas.height).data;
    var b=scenes[1].canvas.getContext('2d').getImageData(0,0,scenes[1].canvas.width,scenes[1].canvas.height).data;
    var delta=0,changed=0,max=0;
    for(var pixel=0;pixel<a.length;pixel+=4){
      var difference=Math.max(Math.abs(a[pixel]-b[pixel]),Math.abs(a[pixel+1]-b[pixel+1]),Math.abs(a[pixel+2]-b[pixel+2]));
      if(difference>3)changed++;
      max=Math.max(max,difference);
      delta+=Math.abs(a[pixel]-b[pixel])+Math.abs(a[pixel+1]-b[pixel+1])+Math.abs(a[pixel+2]-b[pixel+2]);
    }
    var mean=delta/(a.length/4*3),ratio=changed/(a.length/4);
    // Software mode is pixel-exact. GPU mode allows small raster/antialias differences:
    // readback can make the browser select different GPU/CPU paths for the two canvases.
    check(accelerated?mean<.35&&ratio<.03:max===0,'Frame '+progress+': mean RGB difference '+mean.toFixed(4)+', pixels differing >3 '+(ratio*100).toFixed(4)+'%, max '+max);
    if(index===3||index===7||index===11||mean>=.15||ratio>=.005){
      scenes.forEach((s,i)=>captures.push({name:index+'-'+(i?'after':'before'),image:s.canvas.toDataURL('image/png')}));
    }
  });
  for(var progress of [.12,.5,.58,.78,.9]){
    var row={progress:progress};
    scenes.forEach(function(scene,index){
      scene.render(progress);finish(scene);
      var begin=realNow(),js=0;
      for(var frame=0;frame<3;frame++){simulationTime+=16.67;js+=scene.render(progress);finish(scene);}
      row[index?'afterStationary':'beforeStationary']=(realNow()-begin)/3;
      row[index?'afterStationaryJS':'beforeStationaryJS']=js/3;
      begin=realNow();js=0;
      for(var frame=0;frame<3;frame++){simulationTime+=16.67;js+=scene.render(progress+frame*.0002);finish(scene);}
      row[index?'afterMoving':'beforeMoving']=(realNow()-begin)/3;
      row[index?'afterMovingJS':'beforeMovingJS']=js/3;
    });
    timings.push(row);
  }
}catch(error){check(false,error.stack);}
var output=document.createElement('pre');output.id='scene-check-results';output.textContent=JSON.stringify({results:results,timings:timings,captures:captures});document.body.appendChild(output);
'@
$html = '<!doctype html><meta charset="utf-8"><body><script>' + $setup + ($scripts -join "`n") + $checks + '</script></body>'
$html = $html.Replace('HARDWARE_ACCELERATION',$(if ($HardwareAcceleration) {'true'} else {'false'}))
if ($Quick) { $html = $html.Replace('[0,.025,.12,.24,.31,.35,.43,.5,.58,.67,.78,.9,1,.58,.12]','[.12,.58,.9]').Replace('[.12,.5,.58,.78,.9]','[.12,.58,.9]') }
if ($VisualOnly) { $html = $html.Replace('for(var progress of [.12,.5,.58,.78,.9])','for(var progress of [])').Replace('for(var progress of [.12,.58,.9])','for(var progress of [])') }
if ($Profile) {
  $checks = @'
var results=[],timings=[],captures=[];
try{
  scenes.forEach(function(s,index){s.resize();s.render(.58);timings.push({scene:index,profile:s.profile(.5801)});});
}catch(error){results.push({pass:false,name:error.stack});}
var output=document.createElement('pre');output.id='scene-check-results';output.textContent=JSON.stringify({results:results,timings:timings,captures:captures});document.body.appendChild(output);
'@
  $html = '<!doctype html><meta charset="utf-8"><body><script>' + $setup + ($scripts -join "`n") + $checks + '</script></body>'
  $html = $html.Replace('HARDWARE_ACCELERATION',$(if ($HardwareAcceleration) {'true'} else {'false'}))
}
$file = Join-Path $temp 'compare.html'
[IO.File]::WriteAllText($file,$html,[Text.UTF8Encoding]::new($false))
$failed = $false
foreach ($size in $Sizes) {
  $stdout = Join-Path $temp ($size.Replace(',','-') + '.html')
  $stderr = Join-Path $temp ($size.Replace(',','-') + '.log')
  $profile = Join-Path $temp ('profile-' + $size.Replace(',','-'))
  $args = @('--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check','--allow-file-access-from-files',"--force-device-scale-factor=$DeviceScaleFactor", "--user-data-dir=`"$profile`"", "--window-size=$size", '--dump-dom', ('"file:///' + $file.Replace('\','/') + '#' + $size + '"'))
  if ($HardwareAcceleration) { $args = @($args | Where-Object { $_ -ne '--disable-gpu' }) + '--enable-gpu' }
  $process = Start-Process -FilePath $Browser -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $deadline = [DateTime]::UtcNow.AddMinutes(10)
  while (!$process.WaitForExit(10000)) {
    if ([DateTime]::UtcNow -gt $deadline) { $process.Kill(); throw "Browser timed out. Logs: $temp" }
    Write-Output "[$size] Comparing reference and optimized frames..."
  }
  $deadline = [DateTime]::UtcNow.AddMinutes(1)
  do {
    Start-Sleep -Milliseconds 300
    try { $dom = [IO.File]::ReadAllText($stdout) } catch [IO.IOException] { $dom = '' }
  } until ($dom.Contains('</body>') -or [DateTime]::UtcNow -gt $deadline)
  $match = [regex]::Match($dom,'<pre id="scene-check-results">(.*?)</pre>','Singleline')
  if (!$match.Success) { throw "Comparison did not complete. Logs: $temp" }
  $report = [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value) | ConvertFrom-Json
  $report | Select-Object results,timings | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $temp ($size.Replace(',','-') + '.json'))
  foreach ($result in $report.results) { Write-Output ("[$size] " + $(if($result.pass){'PASS'}else{'FAIL'}) + ' ' + $result.name) }
  foreach ($timing in $report.timings) { Write-Output ("[$size] TIMING " + ($timing | ConvertTo-Json -Compress)) }
  foreach ($capture in $report.captures) {
    [IO.File]::WriteAllBytes((Join-Path $temp ($size.Replace(',','-') + '-' + $capture.name + '.png')),[Convert]::FromBase64String(($capture.image -split ',')[1]))
  }
  if (@($report.results | Where-Object { !$_.pass }).Count) { $failed = $true }
}
Write-Output "Reports and screenshots: $temp"
if ($failed) { throw 'Visual comparison failed.' }
