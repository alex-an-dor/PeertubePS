$PtConfig = [ordered]@{
    Url    = ""
    ApiUrl = ""
    Token  = @{
        Type             = ""
        Access           = ""
        Refresh          = ""
        ExpiresIn        = -1
        RefreshExpiresIn = -1
    }
}

#region Converters
Function ConvertTo-PtVideo {
    [CmdletBinding()]
    param(
        $InputObject
    )

    Begin {

    }

    Process {

    }

    End {

    }
}
#endregion Converters

Function Invoke-PtApiRequestSimple {
    [CmdletBinding()]
    param(
        [uri]
        $Uri,

        $Method = "GET",

        $Body
    )

    $Headers = @{
        Authorization = "Bearer $($PtConfig.Token.Access)"
    }
    $RestParams = @{
        Uri     = $Uri
        Method  = $Method
        Headers = $Headers
    }
    if ($Body) {
        $RestParams.Add("Body", $Body)
    }

    try {
        $Response = Invoke-RestMethod @RestParams
        return $Response
    }
    catch {
        Write-Error $_
    }
}

Function Invoke-PtApiRequest {
    [CmdletBinding(DefaultParameterSetName = "Get")]
    param(
        [uri]
        $Uri,

        [String]
        $Method = "GET",

        [hashtable]
        $Headers,

        [parameter(ParameterSetName = "Body")]
        $Body,

        $InFile,

        $ContentType,

        $ConnectionTimeoutSeconds,

        [parameter(ParameterSetName = "Form")]
        $Form,

        [Switch]
        $PassThruRespHeaders
    )

    Write-Debug "Cmdlet: $($MyInvocation.MyCommand.Name)"
    Write-Debug "PSBoundParameters: $($PSBoundParameters | Out-String)"

    if (!$Headers) {
        $Headers = @{
            Authorization = "Bearer $($PtConfig.Token.Access)"
        }
    }
    else {
        $Headers.Add("Authorization", "Bearer $($PtConfig.Token.Access)")
    }

    $RestParams = @{
        Uri                     = $Uri
        Method                  = $Method
        Headers                 = $Headers
        StatusCodeVariable      = "StatusCode"
        ResponseHeadersVariable = "RespHeaders"
    }
    Write-Verbose "Request Uri: $($RestParams.Uri)"

    if ($Body) {
        $RestParams.Add("Body", $Body)
        Write-Debug "Request Body: $($Body | Out-String)"
        if (!$ContentType -and ($Headers.Keys.GetEnumerator() -notcontains "Content-Type")) {
            Write-Debug "Setting `"application/json`" content type"
            $ContentType = "application/json"
        }
        else {
            $ContentType = $null
        }
        #Write-Debug "Request Body: $($RestParams.Body | Out-String)"
    }
    if ($InFile) {
        $RestParams.Add("InFile", $InFile)
    }
    if ($Form) {
        Write-Debug "Request form: $($Form | Out-String)"
        $RestParams.Add("Form", $Form)
    }
    if ($ContentType) {
        $RestParams.Add("ContentType", $ContentType)
    }
    if ($ConnectionTimeoutSeconds) {
        $RestParams.Add("ConnectionTimeoutSeconds", $ConnectionTimeoutSeconds)
    }

    $Start = 0 # paging offset
    $Count = 15 # page size

    try {
        $Response = Invoke-RestMethod @RestParams
        Write-Debug "Last request's status code: $StatusCode"
        Write-Debug "Last request's response headers: $($RespHeaders | Out-String)"

        if ($Response.total -and ($Response.total -gt $Response.data.count)) {
            $Results = @()
            $Results += $Response.data

            Write-Debug "Invoking paging. Total: $($Response.total). On the page: $($Response.Data.Count)"
            do {
                $Start += $Count
                $QParams = @{}
                $QParams['start'] = $Start
                $QParams['count'] = $Count

                # Build request URL
                $PagingUri = "$Uri`?" + $(($QParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&")
                
                $RestParams = @{
                    Uri     = $PagingUri
                    Method  = $Method
                    Headers = $Headers
                }
                Write-Debug "New paging request params: $($RestParams | Out-String)"
                # Make the API request
                try {
                    $Response = Invoke-RestMethod @RestParams
                }
                catch {
                    break
                }

                # Add response data to results
                $Results += $Response.data
            } while ($Response.total -gt $Results.Count)

            if ($PassThruRespHeaders) {
                return $RespHeaders
            }
            return $Results
        }
        else {
            if ($PassThruRespHeaders) {
                return $RespHeaders
            }

            if ($Response.data) {
                return $Response.data
            }

            return $Response
        }
    }
    catch {
        Write-Error $_
    }
}

Function Set-PtSettings {
    [CmdletBinding()]
    param(
        [uri]
        $Url,

        [pscredential]
        $User
    )
    
    $Client = Invoke-RestMethod -Uri $("$Url" + "api/v1/oauth-clients/local")

    try {
        $TokenBody = "client_id=$($Client.client_id)&client_secret=$($Client.client_secret)" + `
            "&grant_type=password&response_type=code" + `
            "&username=$($User.UserName)&password=$($User.Password | ConvertFrom-SecureString -AsPlainText)"
        $Token = Invoke-RestMethod -Uri $("$Url" + "api/v1/users/token") -Method POST -Body $TokenBody

        
        $PtConfig.Url = $Url
        $PtConfig.ApiUrl = $Url.ToString().TrimEnd("/") + "/api/v1"
        $PtConfig.Token.Type = $Token.token_type
        $PtConfig.Token.Access = $Token.access_token
        $PtConfig.Token.Refresh = $Token.refresh_token
        $PtConfig.Token.ExpiresIn = $Token.expires_in
        $PtConfig.Token.RefreshExpiresIn = $Token.refresh_token_expires_in
        
        Write-Verbose "Received API token from $($PtConfig.Url)"
        Write-Verbose "Expires in ~$((New-TimeSpan -Seconds $PtConfig.Token.ExpiresIn).TotalHours) hours."
    }
    catch {
        throw $_
    }
}

Function Add-PtVideoToPlaylist {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true)]
        [String]
        $PlaylistId,

        [parameter(Mandatory = $true)]
        [String]
        $VideoId,

        [int]
        $StartTimestamp,

        [int]
        $StopTimestamp
    )
    
    Write-Debug "Cmdlet: $($MyInvocation.MyCommand.Name)"
    Write-Debug "PSBoundParameters: $($PSBoundParameters | Out-String)"

    $Url = "$($PtConfig.ApiUrl)/video-playlists/$PlaylistId/videos"
    $Body = @{
        "videoId" = $VideoId
    }
    if ($StartTimestamp) {
        $Body.Add("startTimestamp", $StartTimestamp)
    }
    if ($StopTimestamp) {
        $Body.Add("stopTimestamp", $StopTimestamp)
    }
    $RequestBody = $Body | ConvertTo-Json -Depth 10

    $Result = Invoke-PtApiRequest -Uri $Url -Body $RequestBody -Method POST

    return $Result
}

Function Get-PtAccountVideos {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true)]
        [String]
        $Name
    )
    
    Write-Debug "Cmdlet: $($MyInvocation.MyCommand.Name)"
    Write-Debug "PSBoundParameters: $($PSBoundParameters | Out-String)"

    $Url = "$($PtConfig.ApiUrl)/accounts/$Name/videos"
    $Result = Invoke-PtApiRequest -Uri $Url

    return $Result
}

Function Get-PtMyVideos {
    [CmdletBinding()]
    param()
    
    Write-Debug "Cmdlet: $($MyInvocation.MyCommand.Name)"
    Write-Debug "PSBoundParameters: $($PSBoundParameters | Out-String)"

    $Url = "$($PtConfig.ApiUrl)/users/me/videos"
    $Result = Invoke-PtApiRequest -Uri $Url

    return $Result
}

Function Get-PtVideoChannels {
    [CmdletBinding()]
    param(
        [String]
        $Name
    )

    $Url = "$($PtConfig.ApiUrl)/video-channels"
    if ($Name) {
        $Url += "/$Name"
    }
    $Result = Invoke-PtApiRequest -Uri $Url


    return $Result
}

Function Get-PtVideo {
    [CmdletBinding()]
    param(
        $Id
    )

    $Url = "$($PtConfig.ApiUrl)/videos"
    if ($Id) {
        $Url += "/$Id"
    }

    $Result = Invoke-PtApiRequest -Uri $Url

    return $Result
}

Function Get-PtVideoPlaylist {
    [CmdletBinding()]
    param(
        $Id
    )

    $Url = "$($PtConfig.ApiUrl)/video-playlists"
    if ($Id) {
        $Url += "/$Id"
    }

    $Result = Invoke-PtApiRequest -Uri $Url

    return $Result
}


Function Get-PtVideoPrivacyPolicies {
    [CmdletBinding()]
    param()

    $Url = "$($PtConfig.ApiUrl)/videos/privacies"

    $Result = Invoke-PtApiRequest -Uri $Url | ConvertTo-Json | ConvertFrom-Json -AsHashtable

    # inverting int levels and string levels in the hashtable for easier
    $PrivacyLevels = [ordered]@{}
    $Result.GetEnumerator() | Sort-Object $_.Value | ForEach-Object {
        $PrivacyLevels.Add($_.Value, $_.Key)
    }
    return $PrivacyLevels
}

Function Publish-PtVideo {
    [CmdletBinding()]
    param(
        [string]
        $Name,

        [String]
        $LocalPath,

        [string]
        $ChannelId,

        [ValidateScript(
            { $_ -in (Get-PtVideoPrivacyPolicies).Keys }
        )]
        [ArgumentCompleter(
            {
                param($cmd, $param, $wordToComplete)
                # This is the duplicated part of the code in the [ValidateScipt] attribute.
                [array] $validValues = (Get-PtVideoPrivacyPolicies).Keys
                $validValues -like "$wordToComplete*" | ForEach-Object { "'$_'" }
            }
        )]
        [String]
        $Privacy,

        [switch]
        $Resumable
    )

    
    $RestParams = @{
        Method = "POST"
    }

    try {
        $LocalFile = Get-ChildItem $LocalPath
    }
    catch {
        Write-Error $_
        return
    }

    if ($Resumable) {
        #        $FileInBytes = [System.IO.File]::ReadAllBytes($LocalPath)

        # initializing resumable upload
        $Headers = @{
            "X-Upload-Content-Length" = $LocalFile.Length
            "X-Upload-Content-Type"   = "video/mp4"
        }
        $Body = @{
            filename  = (Get-Item -Path $LocalPath).FullName
            channelId = $ChannelId
            name      = $Name
            privacy   = $((Get-PtVideoPrivacyPolicies).GetEnumerator() | Where-Object { $_.Key -match $Privacy }).Value
        }
        $RestParams = @{
            Uri                 = "$($PtConfig.ApiUrl)/videos/upload-resumable"
            Method              = "POST"
            Headers             = $Headers
            Body                = $Body | ConvertTo-Json -Depth 10
            PassThruRespHeaders = $true
        }

        #$RestParams.Add("ContentType", "video/mp4")

        $RespHeaders = Invoke-PtApiRequest @RestParams
        Write-Debug "Resp location: $($RespHeaders.Location)"
        # sort of response uri location validation
        if ($RespHeaders.Location -match "^https:") {
            $UploadId = $(([uri]$RespHeaders.Location).Query.Split("="))[1]
        }
        else {
            $UploadLocation = "https:$($RespHeaders.Location)"
            $UploadId = $(([uri]$UploadLocation).Query.Split("="))[1]
        }
        Write-Debug $UploadId

        # uploading vid's chunks
        $Offset = 0
        $ChunkSize = 1048576
        #do {
        <#
            Write-Debug "Starting upload. Offset: $Offset. Chunk size: $ChunkSize."
            if (($Offset + $ChunkSize - 1) -gt $FileInBytes.Count) {
                $UpperIndex = $FileInBytes.Count
            }
            else {
                $UpperIndex = $Offset + $ChunkSize - 1
            }
            Write-Debug "New upper index: $UpperIndex"
            
            $UploadHeaders = @{
                "Content-Length" = $ChunkSize
                "Content-Range"  = "$Offset-$UpperIndex/$($LocalFile.Length)"
                "Content-Type" = "application/octet-stream"
            }
            $Body = $FileInBytes[$Offset..$UpperIndex]
            
            $UploadRestParams = @{
                Uri         = "$($PtConfig.ApiUrl)/videos/upload-resumable?upload_id=$UploadId"
                Method      = "PUT"
                Headers     = $UploadHeaders
                Body        = $Body
            }
            #>

        # with InFile parameter, it turns out, Invoke-RestMethod will deal with the request headers
        # on its own, no need to chunk it up by hand. I'm vaguely expecting problems with large
        # file size
        $UploadRestParams = @{
            Uri    = "$($PtConfig.ApiUrl)/videos/upload-resumable?upload_id=$UploadId"
            Method = "PUT"
            InFile = $LocalFile
        }
        Invoke-PtApiRequest @UploadRestParams
        #$Offset += $ChunkSize
        #} while ($Offset -lt $LocalFile.Length)
    }
    else {
        $RestParams.Add("Uri", "$($PtConfig.ApiUrl)/videos/upload")
        $Form = @{
            videofile = Get-Item -Path $LocalPath
            channelId = $ChannelId
            name      = $Name
            #TODO: enum на Set-PtSettings? А то страшно выглядит
            privacy   = $((Get-PtVideoPrivacyPolicies).GetEnumerator() | Where-Object { $_.Key -match $Privacy }).Value
        }
        $RestParams.Add("Form", $Form)
        $Result = Invoke-PtApiRequest @RestParams
        Write-Host $RespHeaders.Location
        return $Result
    }
}

Function Set-PtVideo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [String]
        $Id,

        [String]
        $Description,

        [String]
        $Name,

        [ValidateScript(
            { $_ -in (Get-PtVideoPrivacyPolicies).Keys }
        )]
        [ArgumentCompleter(
            {
                param($cmd, $param, $wordToComplete)
                # This is the duplicated part of the code in the [ValidateScipt] attribute.
                [array] $validValues = (Get-PtVideoPrivacyPolicies).Keys
                $validValues -like "$wordToComplete*" | ForEach-Object { "'$_'" }
            }
        )]
        [String]
        $Privacy
    )

    Write-Debug "Cmdlet: $($MyInvocation.MyCommand.Name)"
    Write-Debug "PSBoundParameters: $($PSBoundParameters | Out-String)"

    $Url = "$($PtConfig.ApiUrl)/videos/$Id"
    $Form = @{}
    <# foreach ($Param in $($PSBoundParameters.GetEnumerator() | Where-Object { $_.Key -ne "Id" })) {
        $Form.Add($Param.Key.ToLower(), $Param.Value)
    } #>
    if ($Description) {
        $Form.Add("description", $Description)
    }
    if ($Name) {
        $Form.Add("name", $Name)
    }
    if ($Privacy) {
        $Form.Add("privacy", $((Get-PtVideoPrivacyPolicies).GetEnumerator() | Where-Object { $_.Key -match $Privacy }).Value)
    }
    
    $Result = Invoke-PtApiRequest -Uri $Url -Method PUT -Form $Form

    return $Result
}

