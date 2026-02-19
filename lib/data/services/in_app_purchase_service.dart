import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:flutter/material.dart';

class InAppPurchaseService {
  static final InAppPurchaseService _instance = InAppPurchaseService._internal();

  InAppPurchaseService._internal();

  factory InAppPurchaseService() {
    return _instance;
  }

  final InAppPurchase _iap = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _available = false;
  bool _isInitialized = false;

  // Product IDs for subscriptions
  static const String monthlySubscriptionId = 'monthly_subscription';
  static const String yearlySubscriptionId = 'yearly_subscription';

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    _available = await _iap.isAvailable();
    debugPrint('📱 [IAP] In-App Purchase available: $_available');
    
    if (!_available) {
      debugPrint('⚠️ [IAP] In-App Purchase not available on this device');
      _isInitialized = true;
      return;
    }

    try {
      _subscription = _iap.purchaseStream.listen(
        _handlePurchaseUpdate,
        onError: (error) {
          debugPrint('❌ [IAP] Purchase stream error: $error');
        },
      );
      _isInitialized = true;
      debugPrint('✅ [IAP] In-App Purchase initialized');
    } catch (e) {
      debugPrint('❌ [IAP] Initialization error: $e');
    }
  }

  Future<List<ProductDetails>> fetchProducts(Set<String> productIds) async {
    await initialize();
    
    if (!_available) {
      debugPrint('⚠️ [IAP] In-App Purchase not available');
      return [];
    }

    try {
      debugPrint('📱 [IAP] Fetching products: $productIds');
      final ProductDetailsResponse response =
          await _iap.queryProductDetails(productIds);
      
      debugPrint('📱 [IAP] Response products: ${response.productDetails.map((p) => p.id).toList()}');
      debugPrint('📱 [IAP] Not found IDs: ${response.notFoundIDs}');
      
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('⚠️ [IAP] Not found product IDs: ${response.notFoundIDs}');
      }

      return response.productDetails;
    } catch (e) {
      debugPrint('❌ [IAP] Error fetching products: $e');
      return [];
    }
  }

  Future<bool> purchaseSubscription(ProductDetails product) async {
    if (!_available) {
      debugPrint('⚠️ [IAP] In-App Purchase not available');
      return false;
    }

    try {
      debugPrint('📱 [IAP] Starting purchase for ${product.id}');
      final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
      
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      debugPrint('📱 [IAP] Purchase initiated for ${product.id}');
      return true;
    } catch (e) {
      debugPrint('❌ [IAP] Error initiating purchase: $e');
      return false;
    }
  }

  void _handlePurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      debugPrint('📱 [IAP] Purchase update: ${purchaseDetails.productID} - ${purchaseDetails.status}');
      
      if (purchaseDetails.status == PurchaseStatus.pending) {
        debugPrint('⏳ [IAP] Purchase pending...');
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        debugPrint('❌ [IAP] Purchase error: ${purchaseDetails.error}');
      } else if (purchaseDetails.status == PurchaseStatus.purchased) {
        debugPrint('✅ [IAP] Purchase completed: ${purchaseDetails.productID}');
        _verifyPurchase(purchaseDetails);
      } else if (purchaseDetails.status == PurchaseStatus.restored) {
        debugPrint('✅ [IAP] Purchase restored: ${purchaseDetails.productID}');
      }

      if (purchaseDetails.pendingCompletePurchase) {
        debugPrint('📝 [IAP] Completing purchase...');
        _iap.completePurchase(purchaseDetails);
      }
    }
  }

  void _verifyPurchase(PurchaseDetails purchaseDetails) {
    debugPrint('📋 [IAP] Receipt: ${purchaseDetails.verificationData.serverVerificationData}');
  }

  void dispose() {
    if (_subscription != null) {
      _subscription!.cancel();
    }
  }
}

