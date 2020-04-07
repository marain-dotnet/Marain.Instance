Feature: Deploy assets from a GitHub release
    In order to deploy a Marain instance
    As a developer or administrator
    I want to be able to specify the versions of all the services in an instance in terms of GitHub Releases


# Need ability to use local copy of deployment assets for local dev purposes, to avoid needing a full release cycle

# Fetch release info from GitHub API
# Find all ZIP files relating to deployment (currently pattern-based - <anything>.Deployment.zip)
# Unzip deployment ZIPs locally, and clean them up again once done

# Locate ZIP files to deploy to App Services? Or is that just something done by the individual service scripts
