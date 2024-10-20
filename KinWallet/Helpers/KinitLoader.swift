//
//  KinitLoader.swift
//  Kinit
//

import Foundation
import KinUtil

let nextTaskIdentifier = "Kinit-NextTask"
let availableBackupList = "Kinit-AvailableBackupList"

enum FetchResult<Value> {
    case none(Error?)
    case some(Value)
}

extension FetchResult {
    var value: Value? {
        guard case let FetchResult.some(value) = self else {
            return nil
        }

        return value
    }
}

class KinitLoader {
    fileprivate var delegates = [WeakBox]()
    let offers = Observable<FetchResult<[Offer]>>(.none(nil))
        .stateful()
    let transactions = Observable<FetchResult<[KinitTransaction]>>(.none(nil))
        .stateful()
    let redeemedItems = Observable<FetchResult<[RedeemTransaction]>>(.none(nil))
        .stateful()
    let ecosystemAppCategories = Observable<FetchResult<[EcosystemAppCategory]>>(.none(nil))
        .stateful()

    func loadAllData() {
        loadOffers()
        loadTransactions()
        loadRedeemedItems()
        fetchAvailableBackupHints()
        loadEcosystemApps()
    }

    func loadOffers() {
        loadItems(request: WebRequests.offers(), observable: offers)
    }

    func loadTransactions() {
        loadItems(request: WebRequests.transactionsHistory(), observable: transactions)
    }

    func loadRedeemedItems() {
        loadItems(request: WebRequests.redeemedItems(), observable: redeemedItems)
    }

    func loadEcosystemApps() {
        loadItems(request: WebRequests.KinEcosystem.discoveryApps(), observable: ecosystemAppCategories)
    }

    func loadItems<A, B>(request: WebRequest<A, B>, observable: Observable<FetchResult<B>>) where B: Collection {
        request.withCompletion { result in
            if let collection = result.value, collection.isNotEmpty {
                observable.next(.some(collection))
            } else {
                observable.next(.none(result.error))
            }
        }.load(with: KinWebService.shared)
    }

    func prependTransaction(_ transaction: KinitTransaction) {
        guard let fetchResult = transactions.value else {
            return
        }

        var newTransactions = [KinitTransaction]()
        if case let FetchResult.some(current) = fetchResult {
            if !current.contains(transaction) {
                newTransactions.append(transaction)
            }
            newTransactions.append(contentsOf: current)
        } else {
            newTransactions.append(transaction)
        }

        transactions.next(.some(newTransactions))
    }

    func fetchAvailableBackupHints(skipCache: Bool = false, completion: (([AvailableBackupHint]) -> Void)? = nil) {
        if !skipCache,
            let cachedList: AvailableBackupHintList = SimpleDatastore.loadObject(availableBackupList) {
                completion?(cachedList.hints)
                return
        }

        WebRequests.Backup.availableHints()
            .withCompletion { result in
                guard let list = result.value, list.hints.isNotEmpty else {
                    return
                }

                SimpleDatastore.persist(list, with: availableBackupList)
                completion?(list.hints)
            }.load(with: KinWebService.shared)
    }
}

extension KinitLoader {
    func ecosystemApp(for bundleId: String) -> (app: EcosystemApp, categoryName: String)? {
        guard let categories = ecosystemAppCategories.value?.value else {
            return nil
        }

        guard
            let app = categories
                .flatMap({ $0.apps })
                .first(where: { $0.bundleId == bundleId }),
            let categoryName = categories.first(where: { $0.id == app.categoryId })?.name else {
                return nil
        }

        return (app, categoryName)
    }
}
