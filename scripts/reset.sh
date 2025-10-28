#!/bin/bash

# Ludus Range Redeploy Script for user 'rcr'
# This script removes the existing range and redeploys it

set -e  # Exit on any error

USER="rcr"

echo "=========================================="
echo "Ludus Range Redeploy Script"
echo "User: $USER"
echo "=========================================="
echo ""

# Remove the existing range
echo "[1/4] Removing existing range..."
ludus range rm --user "$USER"
echo "✓ Range removal initiated"
echo ""

# Wait for destruction to complete
echo "[2/4] Waiting for range destruction to complete..."
DESTROY_WAIT=0
MAX_DESTROY_WAIT=300  # 5 minutes max

while [ $DESTROY_WAIT -lt $MAX_DESTROY_WAIT ]; do
    # Get status and strip ANSI color codes
    STATUS=$(ludus range status --user "$USER" 2>/dev/null | grep -v "USER ID" | grep -v "^+" | grep -v "PROXMOX ID" | grep "$USER" | awk -F'|' '{print $6}' | sed 's/\x1b\[[0-9;]*m//g' | tr -d ' ')
    
    echo "Current status: [$STATUS]"
    
    if [ "$STATUS" = "DESTROYED" ]; then
        echo "✓ Range destruction complete"
        break
    elif [ -z "$STATUS" ]; then
        echo "⚠ Could not determine status, assuming destroyed"
        break
    else
        echo "Destruction in progress... (${DESTROY_WAIT}s elapsed)"
        sleep 5
        DESTROY_WAIT=$((DESTROY_WAIT + 5))
    fi
done

if [ $DESTROY_WAIT -ge $MAX_DESTROY_WAIT ]; then
    echo "✗ Range destruction timed out"
    exit 1
fi

echo ""
echo "Waiting 5 seconds for final cleanup..."
sleep 5
echo ""

# Deploy the range
echo "[3/4] Deploying range..."
ludus range deploy --user "$USER"
echo "✓ Deployment started"
echo ""

# Wait for deployment to complete
echo "[4/4] Waiting for deployment to complete..."
echo "Checking status every 10 seconds..."
echo ""

MAX_WAIT=600  # 10 minutes maximum wait time
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    # Get status and strip ANSI color codes
    STATUS=$(ludus range status --user "$USER" 2>/dev/null | grep -v "USER ID" | grep -v "^+" | grep -v "PROXMOX ID" | grep "$USER" | awk -F'|' '{print $6}' | sed 's/\x1b\[[0-9;]*m//g' | tr -d ' ')
    
    echo "Status: [$STATUS] - Elapsed: ${ELAPSED}s"
    
    if [ "$STATUS" = "SUCCESS" ]; then
        echo "✓ Deployment completed successfully!"
        break
    elif [ "$STATUS" = "ERROR" ]; then
        echo "✗ Deployment failed with errors"
        echo ""
        echo "Errors:"
        ludus range errors --user "$USER"
        exit 1
    elif [ "$STATUS" = "DESTROYED" ]; then
        echo "⚠ Range is destroyed - deployment may not have started properly"
        echo "Retrying deployment..."
        ludus range deploy --user "$USER"
    fi
    
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "✗ Deployment timed out after ${MAX_WAIT} seconds"
    echo ""
    echo "Current status:"
    ludus range status --user "$USER"
    exit 1
fi

echo ""
echo "=========================================="
echo "Range Status:"
echo "=========================================="
ludus range status --user "$USER"
echo ""
echo "✓ Redeploy complete!"
