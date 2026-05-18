$url = "http://172.30.0.1/EWA/index.html"

try {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10

    Write-Host "=== Form Info ===" -ForegroundColor Cyan

    if ($response.Forms.Count -gt 0) {
        $i = 0
        foreach ($form in $response.Forms) {
            Write-Host "`n[Form $i]" -ForegroundColor Yellow
            Write-Host "  Action : $($form.Action)"
            Write-Host "  Method : $($form.Method)"
            Write-Host "  Fields :"
            foreach ($field in $form.Fields.GetEnumerator()) {
                Write-Host "    '$($field.Key)' = '$($field.Value)'"
            }
            $i++
        }
    } else {
        Write-Host "No forms detected. Raw HTML:" -ForegroundColor Yellow
        Write-Host $response.Content
    }
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
}
