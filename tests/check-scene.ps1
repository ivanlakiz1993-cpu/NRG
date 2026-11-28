param(
  [string[]]$Sizes = @('390,844','1024,768','1920,1080'),
  [string]$Browser = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (!$Browser) { $Browser = @('C:\Program Files\Google\Chrome\Application\chrome.exe', 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1 }
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
      function moveTo(x){var index=nearestRouteIndex(x,-185,originalRouteEnd);scrollProgress=(index-sceneStart)/(route.length-1-sceneStart);draw();}
      try{
        check(width===viewport[0]&&height===viewport[1],'Exact requested canvas viewport');
        prepareFactoryDetails(finalFactory);
        check(finalFactory.detailPanels.length>30,'Solid workshop equipment and shell exist');
        check(finalFactory.interiorLamps.length===6,'All six current workshop light fixtures');
        check(detailAmount(1,.99)===1,'Late workshop details finish revealing');
        var panes=finalFactory.faces.flatMap(f=>f.windows);
        check(new Set(panes).size===panes.length,'Facade sections do not share mutable windows');
        check(finalFactory.faces.every(f=>f.windows.every(w=>w.points.every(p=>p.every((v,axis)=>v>=Math.min(...f.points.map(q=>q[axis]))-.001&&v<=Math.max(...f.points.map(q=>q[axis]))+.001)))),'Every pane stays inside its own facade');
        moveTo(80);
        check(factoryPower(84,0)===0,'Facade stays dark before energy reaches entrance');
        check(factoryPower(93,0)===0,'Workshop stays dark before connection');
        var hidden=projectInto(96,3.5,-204.5,{});
        check(hidden.visible&&!visibleAt(hidden.x,hidden.y,1/hidden.depth),'Front wall occludes the left machine housing');
        captures.push({name:'approach',image:canvas.toDataURL('image/png')});
        moveTo(99);captures.push({name:'powered-facade',image:canvas.toDataURL('image/png')});
        moveTo(115);
        check(factoryPower(84,0)===1&&factoryPower(184,0)===0,'Entrance powered, rear facade still dark');
        captures.push({name:'entrance',image:canvas.toDataURL('image/png')});
        moveTo(147);
        check(factoryPower(120,0)===1&&factoryPower(165,0)===0,'Lighting follows energy through production bays');
        captures.push({name:'workshop',image:canvas.toDataURL('image/png')});
        for(var lane of [-1,0,1]){
          var cable=buildRibbon(currentRouteIndex,lane).filter(p=>p[0]>=84&&p[0]<=184);
          check(cable.length>0&&cable.every(p=>Math.abs(p[2]+185)<2.1&&p[1]>.05&&p[1]<.5),'Cable '+lane+' clears both portals and stays in channel');
        }
        moveTo(201);
        check(factoryPower(184,0)===1,'Rear facade powers after energy exits');
        captures.push({name:'exit',image:canvas.toDataURL('image/png')});
        moveTo(80);check(factoryPower(84,0)===0,'Reverse scroll restores unpowered state');
        for(var progress of [0,.2,.4,.6,1]){scrollProgress=progress;draw();}
        check(true,'Full route renders without exceptions');
        reduceMotion=true;moveTo(147);check(factoryPower(120,0)===1,'Reduced-motion mode retains deterministic lighting');reduceMotion=false;
        var begin=performance.now();for(var frame=0;frame<3;frame++)draw();
        check(true,'Stationary JavaScript submission average: '+Math.round((performance.now()-begin)/3)+' ms');
        moveTo(147);
        var ribbon=buildRibbon(currentRouteIndex,0),key=depthKey;
        draw();
        check(buildRibbon(currentRouteIndex,0)===ribbon&&depthKey===key,'Stationary frames reuse cable geometry and depth buffer');
        var paths=finalFactory.detailPaths[0].points;
        check(partialPath3D(paths,.5)===partialPath3D(paths,.5),'Unchanged reveal reuses its partial geometry');
        var trace=buildStrokeTrace(paths);draw();
        check(buildStrokeTrace(paths)===trace,'Stationary architecture reuses its visibility trace');
        var visibilityMatches=true;
        for(var sample=0;sample<200;sample++){
          var x=(sample*137%width),y=(sample*73%height),ix=Math.floor(x*depthScale),iy=Math.floor(y*depthScale);
          var nearest=depthBuffer[iy*depthWidth+ix];
          for(var oy=-1;oy<=1;oy++)for(var ox=-1;ox<=1;ox++){
            var nx=ix+ox,ny=iy+oy;
            if(nx>=0&&ny>=0&&nx<depthWidth&&ny<depthHeight)nearest=Math.min(nearest,depthBuffer[ny*depthWidth+nx]);
          }
          var inv=.0001+(sample%37)*.003;
          if(visibleAt(x,y,inv)!==(inv+.12*inv*inv+.00008>=nearest))visibilityMatches=false;
        }
        check(visibilityMatches,'Cached depth neighbourhood preserves conservative occlusion');
        reduceMotion=true;draw();var beforeResize=canvas.toDataURL();resize();
        check(canvas.toDataURL()===beforeResize,'Same-size resize restores background and scene exactly');
        target=scrollProgress;tick(performance.now());
        check(raf===0,'Reduced-motion scene stops requesting unchanged frames');
        reduceMotion=false;
        scrollProgress=target=0;tick(performance.now());
        check(raf===0,'Initial empty scene does not run an idle animation loop');
        moveTo(147);
        var savedDraw=draw,drawCount=0,hiddenDescriptor=Object.getOwnPropertyDescriptor(document,'hidden');
        draw=function(){drawCount++;savedDraw();};
        Object.defineProperty(document,'hidden',{configurable:true,value:true});
        visibilityChanged();tick(performance.now());update();
        check(raf===0&&drawCount===0,'Hidden tab neither renders nor schedules animation');
        if(hiddenDescriptor)Object.defineProperty(document,'hidden',hiddenDescriptor);else delete document.hidden;
        draw=savedDraw;
        if(width<700){moveTo(175);captures.push({name:'mobile-workshop',image:canvas.toDataURL('image/png')});}
        // Inspect the canyon from the river and while climbing the curved dam.
        moveTo(242);captures.push({name:'river-approach',image:canvas.toDataURL('image/png')});
        moveTo(296);captures.push({name:'canyon',image:canvas.toDataURL('image/png')});
        var cliff=projectInto(300,15,-185,{});
        check(cliff.visible&&visibleAt(cliff.x,cliff.y,1/cliff.depth),'River corridor remains open between the detailed cliffs');
        var front=damFront(-185,28,3),behind=damFront(-185,28,-3);
        var frontPixel=projectInto(...front,{}),behindPixel=projectInto(...behind,{});
        check(frontPixel.visible&&visibleAt(frontPixel.x,frontPixel.y,1/frontPixel.depth),'Central dam ascent stays clear of projecting piers');
        check(behindPixel.visible&&!visibleAt(behindPixel.x,behindPixel.y,1/behindPixel.depth),'Solid curved dam hides geometry behind its face');
        moveTo(334);captures.push({name:'dam-outlets',image:canvas.toDataURL('image/png')});
        var visibleJets=outletStreams.filter(p=>buildStrokeTrace(p).hasVisibleSamples);
        check(visibleJets.length>0,'Outlet jets emerge in front of the solid dam');
        var realNow=performance.now.bind(performance),waterFrames=[];
        for(var moment of [1000,1800]){
          performance.now=function(){return moment;};draw();waterFrames.push(canvas.toDataURL());
        }
        check(waterFrames[0]!==waterFrames[1],'Flowing water changes at a stationary camera');
        reduceMotion=true;waterFrames=[];
        for(var moment of [2000,2800]){
          performance.now=function(){return moment;};draw();waterFrames.push(canvas.toDataURL());
        }
        check(waterFrames[0]===waterFrames[1],'Reduced motion keeps the canyon and water stable');
        performance.now=realNow;reduceMotion=false;
        moveTo(355);captures.push({name:'dam-ascent',image:canvas.toDataURL('image/png')});
        scrollProgress=1;draw();captures.push({name:'dam-crest',image:canvas.toDataURL('image/png')});
        moveTo(242);check(buildStrokeTrace(hydroPaths[0].points).hasVisibleSamples,'Reverse travel restores the canyon shoreline');
      }catch(error){results.push({name:error.stack,pass:false});}
      var output=document.createElement('pre');output.id='scene-check-results';output.textContent=JSON.stringify({results:results,captures:captures});document.body.appendChild(output);
'@
$source = $source.Replace('    })();', $checks + "`n    })();")
# Capture script-level errors even if initialization fails before the test hook.
$source = $source.Replace('<head>', '<head><script>window.onerror=function(message){document.documentElement.setAttribute("data-scene-error",message);};</script>')
$file = Join-Path $temp 'scene-check.html'
[IO.File]::WriteAllText($file,$source,[Text.UTF8Encoding]::new($false))
foreach ($size in $Sizes) {
  $stdout = Join-Path $temp ($size.Replace(',','-') + '.html')
  $stderr = Join-Path $temp ($size.Replace(',','-') + '.log')
  $profile = Join-Path $temp ('profile-' + $size.Replace(',','-'))
  $args = @('--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check','--allow-file-access-from-files',"--user-data-dir=`"$profile`"", "--window-size=$size", '--dump-dom', ('"file:///' + $file.Replace('\','/') + '#' + $size + '"'))
  $process = Start-Process -FilePath $Browser -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $deadline = [DateTime]::UtcNow.AddMinutes(5)
  while (!$process.WaitForExit(10000)) {
    if ([DateTime]::UtcNow -gt $deadline) { $process.Kill(); throw "Browser timed out. Logs: $temp" }
    Write-Output "[$size] Checking scene..."
  }
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
