#!/bin/bash

# Test Retail Store Application
# This script verifies all microservices are accessible and healthy

set -e

ALB_URL="http://k8s-ui-ui-2e4c4d4311-1005461520.us-east-1.elb.amazonaws.com"

echo "🧪 Testing Retail Store Application"
echo "===================================="
echo ""

# Test UI
echo "1. Testing UI Service..."
UI_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $ALB_URL --max-time 10)
if [ "$UI_STATUS" = "200" ]; then
    echo "   ✅ UI is accessible (HTTP $UI_STATUS)"
else
    echo "   ❌ UI returned HTTP $UI_STATUS"
fi
echo ""

# Test Catalog API
echo "2. Testing Catalog Service..."
CATALOG_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $ALB_URL/catalogue --max-time 10)
if [ "$CATALOG_STATUS" = "200" ]; then
    echo "   ✅ Catalog API is accessible (HTTP $CATALOG_STATUS)"
else
    echo "   ❌ Catalog API returned HTTP $CATALOG_STATUS"
fi
echo ""

# Test Carts API
echo "3. Testing Carts Service..."
CARTS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $ALB_URL/carts --max-time 10)
if [ "$CARTS_STATUS" = "200" ] || [ "$CARTS_STATUS" = "404" ]; then
    echo "   ✅ Carts API is accessible (HTTP $CARTS_STATUS)"
else
    echo "   ❌ Carts API returned HTTP $CARTS_STATUS"
fi
echo ""

# Test Orders API
echo "4. Testing Orders Service..."
ORDERS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $ALB_URL/orders --max-time 10)
if [ "$ORDERS_STATUS" = "200" ] || [ "$ORDERS_STATUS" = "404" ]; then
    echo "   ✅ Orders API is accessible (HTTP $ORDERS_STATUS)"
else
    echo "   ❌ Orders API returned HTTP $ORDERS_STATUS"
fi
echo ""

# Test Checkout API
echo "5. Testing Checkout Service..."
CHECKOUT_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $ALB_URL/checkout --max-time 10)
if [ "$CHECKOUT_STATUS" = "200" ] || [ "$CHECKOUT_STATUS" = "404" ]; then
    echo "   ✅ Checkout API is accessible (HTTP $CHECKOUT_STATUS)"
else
    echo "   ❌ Checkout API returned HTTP $CHECKOUT_STATUS"
fi
echo ""

# Check ArgoCD Applications
echo "6. Checking ArgoCD Application Status..."
kubectl get application -n argocd --no-headers | while read name sync health rest; do
    if [ "$sync" = "Synced" ] && [ "$health" = "Healthy" ]; then
        echo "   ✅ $name: $sync, $health"
    else
        echo "   ⚠️  $name: $sync, $health"
    fi
done
echo ""

# Check Pod Status
echo "7. Checking Pod Status..."
for ns in ui catalog carts orders checkout; do
    POD_COUNT=$(kubectl get pods -n $ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
    RUNNING_COUNT=$(kubectl get pods -n $ns --no-headers 2>/dev/null | grep Running | wc -l | tr -d ' ')
    if [ "$POD_COUNT" = "$RUNNING_COUNT" ] && [ "$POD_COUNT" != "0" ]; then
        echo "   ✅ $ns: $RUNNING_COUNT/$POD_COUNT pods running"
    else
        echo "   ⚠️  $ns: $RUNNING_COUNT/$POD_COUNT pods running"
    fi
done
echo ""

echo "===================================="
echo "✅ Application Test Complete!"
echo ""
echo "Access the application at:"
echo "   $ALB_URL"
echo ""
echo "Access ArgoCD at:"
echo "   http://k8s-argocd-argocdse-0fafe6a2bf-1764938714.us-east-1.elb.amazonaws.com"
echo ""
