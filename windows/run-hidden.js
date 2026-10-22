// Launcher that runs campus-login.ps1 without showing a console window.
// Starting powershell.exe directly from Task Scheduler flashes a console briefly,
// so start it via wscript.exe with WindowStyle=0 (hidden).
// Usage: wscript.exe //B //Nologo //E:JScript run-hidden.js [args for campus-login.ps1]
var shell = new ActiveXObject("WScript.Shell");
var dir = WScript.ScriptFullName.replace(/\\[^\\]*$/, "");
var cmd = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + dir + '\\campus-login.ps1"';
for (var i = 0; i < WScript.Arguments.length; i++) {
    cmd += " " + WScript.Arguments(i);
}
// 0 = hidden, true = wait and return the exit code
WScript.Quit(shell.Run(cmd, 0, true));
