//
//  WebResources.swift
//  Kinit
//

import Foundation

typealias Success = Bool
typealias TransactionId = String
typealias PublicAddress = String

private struct WebResourceHandlers {
    static func isJSONStatusOk(response: StatusResponse?) -> Bool? {
        return response?.status == "ok"
    }

    static func isRemoteStatusOk(response: RemoteConfigStatusResponse?) -> RemoteConfig? {
        guard
            let response = response,
            WebResourceHandlers.isJSONStatusOk(response: response).boolValue else {
                return nil
        }

        if let config = response.config {
            RemoteConfig.updateCurrent(with: config)
        }

        return response.config
    }

    static func doNothing<T>(response: T) -> T {
        return response
    }
}

struct WebRequests {}

// MARK: User methods

extension WebRequests {
    static func userRegistrationRequest(for user: User) -> WebRequest<RemoteConfigStatusResponse, RemoteConfig> {
        return WebRequest<RemoteConfigStatusResponse, RemoteConfig>(POST: "/user/register",
                                                               body: user,
                                                               transform: WebResourceHandlers.isRemoteStatusOk)
    }

    static func updateDeviceToken(_ newToken: String) -> WebRequest<SimpleStatusResponse, Success> {
        return WebRequest<SimpleStatusResponse, Success>(POST: "/user/push/update-token",
                                                         body: ["token": newToken],
                                                         transform: WebResourceHandlers.isJSONStatusOk)
    }

    static func ackAuthToken(_ authToken: String) -> WebRequest<SimpleStatusResponse, Success> {
        return WebRequest<SimpleStatusResponse, Success>(POST: "/user/auth/ack",
                                                         body: ["token": authToken],
                                                         transform: WebResourceHandlers.isJSONStatusOk)
    }

    static func updateUserIdToken(_ idToken: String) -> WebRequest<PhoneVerificationStatusResponse, [Int]> {
        let transform: (PhoneVerificationStatusResponse?) -> [Int]? = {
            guard
                let response = $0,
                WebResourceHandlers.isJSONStatusOk(response: response).boolValue else {
                    return nil
            }

            return response.hints
        }

        return WebRequest<PhoneVerificationStatusResponse, [Int]>(POST: "/user/firebase/update-id-token",
                                                                  body: ["token": idToken],
                                                                  transform: transform)
    }

    static func appLaunch() -> WebRequest<RemoteConfigStatusResponse, RemoteConfig> {
        return WebRequest<RemoteConfigStatusResponse, RemoteConfig>(POST: "/user/app-launch",
                                                                    body: ["app_ver": Bundle.appVersion],
                                                                    transform: WebResourceHandlers.isRemoteStatusOk)
    }

    static func searchPhoneNumber(_ phoneNumber: String) -> WebRequest<ContactSearchStatusResponse, PublicAddress> {
        return WebRequest<ContactSearchStatusResponse, PublicAddress>(POST: "/user/contact",
                                                                      body: ["phone_number": phoneNumber],
                                                               transform: { response -> PublicAddress? in
            guard let response = response,
                WebResourceHandlers.isJSONStatusOk(response: response).boolValue,
                let address = response.address else {
                    return nil
            }

            return address
        })
    }
}

// MARK: Kin Onboard
extension WebRequests {
    static func createAccount(with publicAddress: String) -> WebRequest<SimpleStatusResponse, Success> {
        return WebRequest<SimpleStatusResponse, Success>(POST: "/user/onboard",
                                                         body: ["public_address": publicAddress],
                                                         transform: WebResourceHandlers.isJSONStatusOk)
    }
}

// MARK: Earn
extension WebRequests {
    static func taskCategories() -> WebRequest<TaskCategoriesResponse, TaskCategoriesResponse> {
        return WebRequest<TaskCategoriesResponse, TaskCategoriesResponse>(GET: "/user/categories",
                                                                          transform: WebResourceHandlers.doNothing)
    }

    static func tasks(for categoryId: String) -> WebRequest<CategoryTasksResponse, CategoryTasksResponse> {
        return WebRequest<CategoryTasksResponse, CategoryTasksResponse>(GET: "/user/category/\(categoryId)/tasks",
            transform: WebResourceHandlers.doNothing)
    }

    static func nextTasks() -> WebRequest<TasksByCategoryResponse, [String: [Task]]> {
        return WebRequest<TasksByCategoryResponse, [String: [Task]]>(GET: "/user/tasks",
                                                 transform: { $0?.tasks })
    }

    static func submitTaskResults(_ results: TaskResults) -> WebRequest<SimpleStatusResponse, Success> {
        return WebRequest<SimpleStatusResponse, Success>(POST: "/user/task/results",
                                                      body: results,
                                                      transform: WebResourceHandlers.isJSONStatusOk)
    }
}

// MARK: Spend
extension WebRequests {
    static func offers() -> WebRequest<OffersResponse, [Offer]> {
        return WebRequest<OffersResponse, [Offer]>(GET: "/user/offers",
                                                   transform: { $0?.offers })
    }

    static func bookOffer(_ offer: Offer) -> WebRequest<BookOfferResponse, BookOfferResult> {
        let transform: (BookOfferResponse?) -> BookOfferResult? = { bookOfferReponse -> BookOfferResult? in
            guard
                let response = bookOfferReponse,
                WebResourceHandlers.isJSONStatusOk(response: bookOfferReponse).boolValue,
                let orderId = response.orderId else {
                return nil
            }

            return .success(orderId)
        }

        return WebRequest<BookOfferResponse, BookOfferResult>(POST: "/offer/book",
                                                     body: OfferInfo(identifier: offer.identifier),
                                                     transform: transform)
    }

    static func redeemOffer(with paymentReceipt: PaymentReceipt) -> WebRequest<RedeemResponse, [RedeemGood]> {
        let transform: (RedeemResponse?) -> [RedeemGood]? = {
            guard
                let response = $0,
                WebResourceHandlers.isJSONStatusOk(response: response).boolValue else {
                    return nil
            }

            return response.goods
        }

        return WebRequest<RedeemResponse, [RedeemGood]>(POST: "/offer/redeem",
                                                        body: paymentReceipt,
                                                        transform: transform)
    }

    static func reportTransaction(with txId: String,
                                  amount: UInt64,
                                  to address: String) -> WebRequest<TransactionReportStatusResponse, Success> {
        //swiftlint:disable:next nesting
        struct PeerToPeerReport: Codable {
            let tx_hash: String
            let amount: UInt64
            let destination_address: String
        }

        let transform: (TransactionReportStatusResponse?) -> Success? = {
            guard let response = $0,
                WebResourceHandlers.isJSONStatusOk(response: response).boolValue else {
                return false
            }

            let tx = response.transaction
            DataLoaders.kinit.prependTransaction(tx)

            return true
        }

        let body = PeerToPeerReport(tx_hash: txId, amount: amount, destination_address: address)
        return WebRequest<TransactionReportStatusResponse, Success>(POST: "/user/transaction/p2p",
                                                                    body: body,
                                                                    transform: transform)
    }
}

// MARK: History

extension WebRequests {
    static func transactionsHistory() -> WebRequest<TransactionHistoryResponse, [KinitTransaction]> {
        let transform: (TransactionHistoryResponse?) -> [KinitTransaction]? = {
            guard
                let response = $0,
                WebResourceHandlers.isJSONStatusOk(response: response).boolValue else {
                return nil
            }

            return response.transactions
        }

        return WebRequest<TransactionHistoryResponse, [KinitTransaction]>(GET: "/user/transactions",
                                                                          transform: transform)
    }

    static func redeemedItems() -> WebRequest<RedeemedItemsResponse, [RedeemTransaction]> {
        let transform: (RedeemedItemsResponse?) -> [RedeemTransaction]? = {
            guard
                let response = $0,
                WebResourceHandlers.isJSONStatusOk(response: response).boolValue else {
                    return nil
            }

            return response.items
        }

        return WebRequest<RedeemedItemsResponse, [RedeemTransaction]>(GET: "/user/redeemed",
                                                                          transform: transform)
    }
}

// MARK: Blacklists

extension WebRequests {
    struct Blacklists {
        static func areaCodes() -> WebRequest<BlacklistedAreaCodes, [String]> {
            return WebRequest<BlacklistedAreaCodes, [String]>(GET: "/blacklist/areacodes",
                                                              transform: { $0?.areaCodes })
        }
    }
}

// MARK: Backup

extension WebRequests {
    typealias BackupHintListRequest = WebRequest<AvailableBackupHintList, AvailableBackupHintList>

    struct Backup {
        static func availableHints() -> BackupHintListRequest {
            return BackupHintListRequest(GET: "/backup/hints", transform: WebResourceHandlers.doNothing)
        }

        static func submitHints(_ hints: [Int]) -> WebRequest<EmptyResponse, EmptyResponse> {
            let hintsToSubmit = ChosenBackupHints(hints: hints)
            return WebRequest<EmptyResponse, EmptyResponse>(POST: "/user/backup/hints",
                                                            body: hintsToSubmit,
                                                            transform: WebResourceHandlers.doNothing)
        }

        static func submittedQuestionsIds() -> WebRequest<ChosenBackupHints, [Int]> {
            return WebRequest<ChosenBackupHints, [Int]>(GET: "/user/backup/hints",
                                                        transform: { $0?.hints })
        }

        static func sendEmail(to address: String, encryptedKey: String) -> WebRequest<SimpleStatusResponse, Success> {
            let body = ["to_address": address, "enc_key": encryptedKey]
            return WebRequest<SimpleStatusResponse, Success>(POST: "/user/email_backup",
                                                             body: body,
                                                             transform: WebResourceHandlers.isJSONStatusOk)
        }

        static func restoreUserId(with address: String) -> WebRequest<RestoreUserIdResponse, String> {
            let transform: (RestoreUserIdResponse?) -> String? = {
                return $0?.userId
            }

            return WebRequest<RestoreUserIdResponse, String>(POST: "/user/restore",
                                                             body: ["address": address],
                                                             transform: transform)
        }
    }
}

//MARK: App Discovery

extension WebRequests {
    struct KinEcosystem {
        static func discoveryApps() -> WebRequest<[EcosystemAppCategory], [EcosystemAppCategory]> {
            return WebRequest<[EcosystemAppCategory], [EcosystemAppCategory]>(GET: "/app_discovery",
                                                                              transform: WebResourceHandlers.doNothing)
        }
    }
}
