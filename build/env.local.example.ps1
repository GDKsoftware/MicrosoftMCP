# Copy to build/env.local.ps1 and adjust to your machine. env.local.ps1 is ignored by git.

# Delphi installation and common folder.
# $env:BDS_ROOT = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
# $env:BDS_COMMON = 'C:\Users\Public\Documents\Embarcadero\Studio\37.0'

# Linux64 SDK imported through the PAServer SDK manager, and the WSL distro that runs the Linux64 tests.
# $env:LINUX_SDK_ROOT = "$env:USERPROFILE\Documents\Embarcadero\Studio\SDKs\ubuntu26.04.sdk"
# $env:WSL_DISTRO = 'Ubuntu-24.04'

# Folder with libcrypto-3-x64.dll and libssl-3-x64.dll, copied next to the Win64 executables.
# $env:OPENSSL_DIR = 'C:\Program Files\OpenSSL-Win64\bin'

# Folder with libpq.dll for the Win64 FireDAC mailbox store tests; by default the newest C:\Program Files\PostgreSQL\<n>\bin.
# $env:PG_BIN_DIR = 'C:\Program Files\PostgreSQL\17\bin'

# Run the FireDAC mailbox store tests against the test database of build/docker-compose.yml (test-only credentials).
# Without this variable those tests pass without touching a database.
# $env:MICROSOFTMCP_TEST_PG = 'DriverID=PG;Server=127.0.0.1;Port=55432;Database=microsoftmcp_test;User_Name=microsoftmcp_test;Password=microsoftmcp_test'
