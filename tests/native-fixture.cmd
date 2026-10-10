@echo off
if "%LEGRABBER_TEST_MODE%"=="success" goto success
if "%LEGRABBER_TEST_MODE%"=="partial" goto partial
if "%LEGRABBER_TEST_MODE%"=="json" goto json
if "%LEGRABBER_TEST_MODE%"=="search" goto search
if "%LEGRABBER_TEST_MODE%"=="badjson" goto badjson
if "%LEGRABBER_TEST_MODE%"=="empty" exit /b 0
if "%LEGRABBER_TEST_MODE%"=="errorzero" goto errorzero
if "%LEGRABBER_TEST_MODE%"=="retry" goto retry
echo ERROR: fixture format unavailable 1>&2
exit /b 7
:success
echo [youtube:tab] fixture: Downloading webpage
echo [download] Destination: C:\fixture\track.webm
echo [download] 100.0%% of 1MiB
echo LEGRABBER_OUT:C:\fixture\track.webm
exit /b 0
:partial
echo [download] Downloading item 1 of 2
echo LEGRABBER_OUT:C:\fixture\track.webm
echo ERROR: fixture second item unavailable 1>&2
exit /b 1
:json
echo WARNING: fixture warning on stderr 1>&2
echo {"id":"fixture","title":"Fixture title","formats":[]}
exit /b 0
:badjson
echo this is not JSON
exit /b 0
:search
echo WARNING: fixture search warning 1>&2
echo {"entries":[null,{"id":"abcdefghijk","title":"First result","channel":"First channel","duration":125},{"id":"abcdefghijk","title":"Duplicate"},{"id":"not-valid","title":"Invalid"},{"id":"-abcdefghij","title":"Second result","uploader":"Second channel"}]}
exit /b 0
:errorzero
echo LEGRABBER_OUT:C:\fixture\track.webm
echo ERROR: fixture postprocessing failed 1>&2
exit /b 0
:retry
if exist "%LEGRABBER_TEST_RETRY_STATE%" goto retried
echo first>"%LEGRABBER_TEST_RETRY_STATE%"
echo LEGRABBER_OUT:C:\fixture\track.webm
echo ERROR: HTTP Error 403: Forbidden 1>&2
exit /b 1
:retried
echo LEGRABBER_OUT:C:\fixture\track.webm
exit /b 0
