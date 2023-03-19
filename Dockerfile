# Use a base image with PowerShell installed
FROM mcr.microsoft.com/powershell:7.2.0-ubuntu-20.04

# Copy the PowerShell script into the image
COPY my-script.ps1 /app/my-script.ps1

# install dependencies
RUN pwsh -c "&{ Install-Module Az.Accounts -Force }"
RUN pwsh -c "&{ Get-Module -Name Az.Accounts -All }"

# Set the working directory to the location of the script
WORKDIR /app

# Set the default command to run the script
CMD [ "pwsh", "-command", "./my-script.ps1" ]
