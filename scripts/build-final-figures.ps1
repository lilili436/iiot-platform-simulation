param([Parameter(Mandatory=$true)][string]$ReportDir)
$ErrorActionPreference="Stop"
Add-Type -AssemblyName System.Windows.Forms.DataVisualization
Add-Type -AssemblyName System.Drawing
$csv=Join-Path $ReportDir "aggregate.csv"
if(!(Test-Path -LiteralPath $csv)){return}
$rows=@(Import-Csv -LiteralPath $csv)
$figures=Join-Path $ReportDir "figures"
New-Item -ItemType Directory -Path $figures -Force|Out-Null
foreach($plot in @(@("service-ratio","ready_ratio_mean","Mean service ready ratio"),@("workflow-ratio","workflow_ratio_mean","Mean complete workflow ratio"),@("planning-time","planning_median_ms","Median planning time (ms)"))){
 $chart=New-Object System.Windows.Forms.DataVisualization.Charting.Chart
 try{
  $chart.Width=1400;$chart.Height=650;$chart.BackColor=[Drawing.Color]::White
  $area=New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
  $area.AxisX.Interval=1;$area.AxisX.LabelStyle.Angle=-35;$area.AxisX.MajorGrid.Enabled=$false
  $area.AxisY.Title=$plot[2];$area.AxisY.MajorGrid.LineColor=[Drawing.Color]::LightGray
  if($plot[0] -ne "planning-time"){$area.AxisY.Minimum=0;$area.AxisY.Maximum=1}
  $chart.ChartAreas.Add($area)
  $legend=New-Object System.Windows.Forms.DataVisualization.Charting.Legend;$legend.Docking="Top";$chart.Legends.Add($legend)
  foreach($objective in @("service_first","workflow_first")){
   $series=New-Object System.Windows.Forms.DataVisualization.Charting.Series($objective)
   $series.ChartType="Column";$series.Font=New-Object Drawing.Font("Segoe UI",10)
   foreach($method in @("first_fit","round_robin","best_fit","beam_input_w64","beam_scarcity_w4","beam_scarcity_w16","beam_scarcity_w64")){
    $values=@($rows|Where-Object {$_.objective -eq $objective -and $_.method -eq $method}|ForEach-Object{[double]::Parse($_.($plot[1]),[cultureinfo]::InvariantCulture)})
    $value=if($plot[0] -eq "planning-time"){$ordered=@($values|Sort-Object);$middle=[int][math]::Floor($ordered.Count/2);if($ordered.Count%2){$ordered[$middle]}else{($ordered[$middle-1]+$ordered[$middle])/2}}else{($values|Measure-Object -Average).Average}
    [void]$series.Points.AddXY($method,$value)
   }
   $chart.Series.Add($series)
  }
  [void]$chart.Titles.Add($plot[2]+" | synthetic paired scenarios; see stratified CSV")
  $chart.SaveImage((Join-Path $figures ($plot[0]+".png")),"Png")
 }finally{$chart.Dispose()}
}
