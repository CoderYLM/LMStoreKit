//
//  LmIapTool.swift
//  
//
//  Created by qmp-yangluming on 2025/4/28.
//

import Foundation
import SwiftyStoreKit
import StoreKit

@objc public class IAPProduct: NSObject {
    @objc public let productId: String
    @objc public let localizedTitle: String
    @objc public let localizedPrice: String
    @objc public let price: NSDecimalNumber
    
    init(product: SKProduct) {
        self.productId = product.productIdentifier
        self.localizedTitle = product.localizedTitle
        self.localizedPrice = product.localizedPrice ?? ""
        self.price = product.price
        
        let info: [String: Any] = ["productId": product.productIdentifier, "localizedTitle": product.localizedTitle, "localizedPrice": product.localizedPrice ?? "", "price": product.price]
        // 缓存
        UserDefaults.standard.set(info, forKey: "IAPProduct_Product_\(product.productIdentifier)")
    }
    @objc
    init?(productId: String) {
        guard let info = UserDefaults.standard.dictionary(forKey: "IAPProduct_Product_\(productId)") else {
            return nil
        }
        self.productId = info["productId"] as? String ?? ""
        self.localizedTitle = info["localizedTitle"] as? String ?? ""
        self.localizedPrice = info["localizedPrice"] as? String ?? ""
        self.price = info["price"] as? NSDecimalNumber ?? .zero
    }
}

extension SKProduct {
    var localizedPrice: String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = self.priceLocale
        return formatter.string(from: self.price)
    }
}

@objcMembers
public final class SubscriptionManager: NSObject {
    
    public static let shared = SubscriptionManager()
    private override init() {}
    
    private var productIdentifiers: Set<String> = []
    private var sharedSecret: String = ""
    private let subscriptionExpiryDateKey = "subscriptionExpiryDate"
    @objc public static let subscriptionStatusChanged = "subscriptionStatusChanged"
    
    private var availableProducts: [SKProduct] = []
    
    public func configure(productIdentifiers: Set<String>, sharedSecret: String) {
        self.productIdentifiers = productIdentifiers
        self.sharedSecret = sharedSecret
    }
    
    public func start() {
        SwiftyStoreKit.completeTransactions(atomically: false) { purchases in
            self.verifyReceipt { _, success in
                guard success else { return }
                purchases.forEach { purchase in
                    if purchase.needsFinishTransaction {
                        SwiftyStoreKit.finishTransaction(purchase.transaction)
                    }
                }
            }
        }
    }
    
    // MARK: - 查询商品
    public func fetchAvailableProducts(_ completion: @escaping ([IAPProduct]?, NSError?) -> Void) {
        if !availableProducts.isEmpty {
            let products = availableProducts.map { IAPProduct(product: $0) }
            completion(products, nil)
            return
        }
        
        SwiftyStoreKit.retrieveProductsInfo(productIdentifiers) { result in
            if let error = result.error as NSError? {
                completion(nil, error)
                return
            }
            
            self.availableProducts = Array(result.retrievedProducts)
            let products = self.availableProducts.map { IAPProduct(product: $0) }
            completion(products, nil)
        }
    }
    
    // MARK: - 购买订阅
    public func purchase(productId: String, completion: @escaping (Bool, String?) -> Void) {
        SwiftyStoreKit.purchaseProduct(productId, atomically: false) { result in
            switch result {
            case .success(let purchase):
                print("✅ 购买成功: \(purchase.productId)")
                self.verifyReceipt { isValid, success in
                    if success {
                        if purchase.needsFinishTransaction {
                            SwiftyStoreKit.finishTransaction(purchase.transaction)
                        }
                        completion(isValid, isValid ? "Successful" : "Unsuccessful")
                    } else {
                        completion(false, "Unsuccessful")
                    }
                }
            case .error(let error):
                print("❌ 购买失败: \(error)")
                let message: String
                switch error.code {
                case .unknown: message = "Unknown error"
                case .clientInvalid: message = "Client Invalid"
                case .paymentCancelled: message = "Subscription Canceled"
                case .paymentInvalid: message = "Payment invalid"
                case .paymentNotAllowed: message = "Payment not allowed"
                default: message = error.localizedDescription
                }
                completion(false, message)
            }
        }
    }
    
    // MARK: - 恢复购买
    public func restorePurchases(_ completion: @escaping (Bool, String?) -> Void) {
        SwiftyStoreKit.restorePurchases(atomically: false) { results in
            if !results.restoreFailedPurchases.isEmpty {
                completion(false, "Unsubscribed")
                return
            }
            
            self.verifyReceipt { isValid, success in
                if success {
                    results.restoredPurchases.forEach { purchase in
                        if purchase.needsFinishTransaction {
                            SwiftyStoreKit.finishTransaction(purchase.transaction)
                        }
                    }
                    completion(isValid, isValid ? "Successful" : "Unsubscribed")
                } else {
                    completion(false, "Unsubscribed")
                }
            }
        }
    }
    
    @objc
    public static var receiptJson: String?
    
    // MARK: - 校验收据（判断是否订阅有效）
    public func verifyReceipt(_ completion: @escaping (_ isValid: Bool, _ success: Bool) -> Void) {
        let validator = AppleReceiptValidator(sharedSecret: sharedSecret)
        
        SwiftyStoreKit.verifyReceipt(using: validator) { result in
            switch result {
            case .success(let receipt):
                if let receiptData = try? JSONSerialization.data(withJSONObject: receipt, options: .withoutEscapingSlashes), let receiptJson = String.init(data: receiptData, encoding: .utf8) {
                    SubscriptionManager.receiptJson = receiptJson
                }
                
                var latestExpiryDate: Date?
                
                for productId in self.productIdentifiers {
                    let status = SwiftyStoreKit.verifySubscription(
                        ofType: .autoRenewable,
                        productId: productId,
                        inReceipt: receipt
                    )
                    
                    switch status {
                    case .purchased(let expiryDate, _):
                        if expiryDate > Date() {
                            print("✅ 订阅有效: \(productId), 到期: \(expiryDate)")
                            if latestExpiryDate == nil || expiryDate > latestExpiryDate! {
                                latestExpiryDate = expiryDate
                            }
                        }
                    case .expired(_, _), .notPurchased:
                        continue
                    }
                }
                
                UserDefaults.standard.set(latestExpiryDate, forKey: self.subscriptionExpiryDateKey)
                NotificationCenter.default.post(name: NSNotification.Name(SubscriptionManager.subscriptionStatusChanged), object: nil)
                completion(latestExpiryDate != nil, true)
            case .error(let error):
                print("❌ 收据校验失败: \(error.localizedDescription)")
                UserDefaults.standard.removeObject(forKey: self.subscriptionExpiryDateKey)
                NotificationCenter.default.post(name: NSNotification.Name(SubscriptionManager.subscriptionStatusChanged), object: nil)
                completion(false, false)
            }
        }
    }
    
    // MARK: - 查询本地存储的订阅是否已过期
    public func isSubscriptionExpired() -> Bool {
        guard let expiryDate = UserDefaults.standard.object(forKey: subscriptionExpiryDateKey) as? Date else {
            return true
        }
        return expiryDate <= Date()
    }
}

//        var now = Date()
//        var latestExpiryDate = Calendar.current.date(byAdding: .day, value: 7, to: now)
//        UserDefaults.standard.set(latestExpiryDate, forKey: self.subscriptionExpiryDateKey)
//        NotificationCenter.default.post(name: NSNotification.Name(SubscriptionManager.subscriptionStatusChanged), object: nil)
//        completion(true, "")
//        return;
