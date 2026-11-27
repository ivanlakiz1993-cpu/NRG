$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$browser = @('C:\Program Files\Google\Chrome\Application\chrome.exe', 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1
if (!$browser) { throw 'Chrome or Edge is required for the browser checks.' }
$temp = Join-Path ([IO.Path]::GetTempPath()) ('nrg-scene-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
$source = [IO.File]::ReadAllText((Join-Path $root 'energy-3d-scene.html'))
$checks = @'
      var viewport=location.hash.slice(1).split(',').map(Number);
      document.querySelector('.screen').style.width=viewport[0]+'px';
      document.querySelector('.screen').style.height=viewport[1]+'px';resize();
      cancelAnimationFrame(raf);raf=0;
      var results=[],captures=[];
      function check(condition,name){results.push({name:name,pass:!!condition});}
      function moveTo(x){currentRouteIndex=nearestRouteIndex(x,-185,originalRouteEnd);scrollProgress=currentRouteIndex/(route.length-1);draw();}
      try{
        check(width===viewport[0]&&height===viewport[1],'Exact requested canvas viewport');
        prepareFactoryDetails(finalFactory);
        check(finalFactory.detailPanels.length>30,'Solid workshop equipment and shell exist');
        check(finalFactory.powerBranches.length===4,'Four production feeders');
        check(finalFactory.interiorLamps.length===9,'Nine independently powered light fixtures');
        check(detailAmount(1,.99)===1,'Late workshop details finish revealing');
        var panes=finalFactory.faces.flatMap(f=>f.windows);
        check(new Set(panes).size===panes.length,'Facade sections do not share mutable windows');
        check(finalFactory.faces.every(f=>f.windows.every(w=>w.points.every(p=>p.every((v,axis)=>v>=Math.min(...f.points.map(q=>q[axis]))-.001&&v<=Math.max(...f.points.map(q=>q[axis]))+.001)))),'Every pane stays inside its own facade');
        moveTo(80);
        check(factoryPower(164,0)===0,'Facade stays dark before energy reaches entrance');
        check(factoryPower(173,0)===0,'Workshop stays dark before connection');
        var hidden=projectInto(176,3.5,-204.5,{});
        check(hidden.visible&&!visibleAt(hidden.x,hidden.y,1/hidden.depth),'Front wall occludes the left machine housing');
        captures.push({name:'approach',image:canvas.toDataURL('image/png')});
        moveTo(180);captures.push({name:'powered-facade',image:canvas.toDataURL('image/png')});
        moveTo(180);
        check(factoryPower(164,0)===1&&factoryPower(264,0)===0,'Entrance powered, rear facade still dark');
        captures.push({name:'entrance',image:canvas.toDataURL('image/png')});
        moveTo(220);
        check(factoryPower(200,0)===1&&factoryPower(245,0)===0,'Lighting follows energy through production bays');
        captures.push({name:'workshop',image:canvas.toDataURL('image/png')});
        for(var lane of [-1,0,1]){
          var cable=buildRibbon(currentRouteIndex,lane).filter(p=>p[0]>=164&&p[0]<=264);
          check(cable.length>0&&cable.every(p=>Math.abs(p[2]+185)<2.1&&p[1]>.05&&p[1]<.5),'Cable '+lane+' clears both portals and stays in channel');
        }
        moveTo(300);
        check(factoryPower(264,0)===1,'Rear facade powers after energy exits');
        captures.push({name:'exit',image:canvas.toDataURL('image/png')});
        moveTo(80);check(factoryPower(164,0)===0,'Reverse scroll restores unpowered state');
        for(var progress of [0,.2,.4,.6,1]){scrollProgress=progress;draw();}
        check(true,'Full route renders without exceptions');
        reduceMotion=true;moveTo(220);check(factoryPower(200,0)===1,'Reduced-motion mode retains deterministic lighting');reduceMotion=false;
        var begin=performance.now();for(var frame=0;frame<3;frame++)draw();
        check(true,'Stationary frame average: '+Math.round((performance.now()-begin)/3)+' ms');
        moveTo(220);
        if(width<700){moveTo(245);captures.push({name:'mobile-workshop',image:canvas.toDataURL('image/png')});}
      }catch(error){results.push({name:error.stack,pass:false});}
      var output=document.createElement('pre');output.id='scene-check-results';output.textContent=JSON.stringify({results:results,captures:captures});document.body.appendChild(output);
'@
$source = $source.Replace('    })();', $checks + "`n    })();")
# Capture script-level errors even if initialization fails before the test hook.
$source = $source.Replace('<head>', '<head><script>window.onerror=function(message){document.documentElement.setAttribute("data-scene-error",message);};</script>')
$file = Join-Path $temp 'scene-check.html'
[IO.File]::WriteAllText($file,$source,[Text.UTF8Encoding]::new($false))
foreach ($size in @('1440,900','390,844')) {
  $stdout = Join-Path $temp ($size.Replace(',','-') + '.html')
  $stderr = Join-Path $temp ($size.Replace(',','-') + '.log')
  $profile = Join-Path $temp ('profile-' + $size.Replace(',','-'))
  $args = @('--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check','--allow-file-access-from-files',"--user-data-dir=`"$profile`"", "--window-size=$size", '--dump-dom', ('"file:///' + $file.Replace('\','/') + '#' + $size + '"'))
  $process = Start-Process -FilePath $browser -ArgumentList $args -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  if (!$process.WaitForExit(120000)) { $process.Kill(); throw "Browser timed out. Logs: $temp" }
  $deadline = [DateTime]::UtcNow.AddSeconds(120)
  do {
    Start-Sleep -Milliseconds 300
    try { $dom = [IO.File]::ReadAllText($stdout) } catch [IO.IOException] { $dom = '' }
  } until ($dom.Contains('</html>') -or [DateTime]::UtcNow -gt $deadline)
  $match = [regex]::Match($dom,'<pre id="scene-check-results">(.*?)</pre>','Singleline')
  if (!$match.Success) { throw "Browser checks did not complete. Logs: $temp" }
  $report = [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value) | ConvertFrom-Json
  foreach ($result in $report.results) { Write-Output ("[$size] " + $(if($result.pass){'PASS'}else{'FAIL'}) + ' ' + $result.name) }
  foreach ($capture in $report.captures) {
    $path = Join-Path $temp ($size.Replace(',','-') + '-' + $capture.name + '.png')
    [IO.File]::WriteAllBytes($path,[Convert]::FromBase64String(($capture.image -split ',')[1]))
  }
  if (@($report.results | Where-Object { !$_.pass }).Count) { throw "Scene assertions failed. Screenshots: $temp" }
}
Write-Output "Browser checks passed. Screenshots: $temp"
