//
//  SurveyUnavailableViewController.swift
//  Kinit
//

import UIKit

final class SurveyUnavailableViewController: UIViewController {
    var task: Task?
    var taskCategory: String!
    var error: Error?
    var noticeViewController: NoticeViewController?

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        displayUnavailabilityReason()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(displayUnavailabilityReason),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
    }

    @objc func displayUnavailabilityReason() {
        let noticeContent: NoticeContent
        var displayType = Notice.DisplayType.imageFirst

        if let task = task {
            let toUnlock = task.daysToUnlock
            displayType = .titleFirst

            noticeContent = .init(title: L10n.NextActivityOn.title(task.nextAvailableDay()),
                                  message: L10n.NextActivityOn.message,
                                  image: Asset.sowingIllustration.image)

            Events.Analytics
                .ViewLockedTaskPage(timeToUnlock: Int(toUnlock))
                .send()
        } else {
            if let error = error {
                noticeContent = .fromError(error)

                let errorType: Events.ErrorType = error.isInternetError ? .internetConnection : .generic
                let failureReason = error.localizedDescription
                Events.Analytics
                    .ViewErrorPage(errorType: errorType, failureReason: failureReason)
                    .send()
            } else {
                noticeContent = .init(title: L10n.noActivitiesTitle,
                                      message: L10n.noActivitiesMessage,
                                      image: Asset.noTasksIlustration.image)
                Events.Analytics
                    .ViewEmptyStatePage(menuItemName: .earn,
                                        taskCategory: taskCategory)
                    .send()
            }
        }

        notifyButtonIfNeeded { [weak self] buttonConfiguration in
            self?.children.first?.remove()
            self?.noticeViewController = self?.addNoticeViewController(with: noticeContent,
                                                                       buttonConfiguration: buttonConfiguration,
                                                                       displayType: displayType,
                                                                       delegate: self)
        }
    }

    private func notifyButtonIfNeeded(completion: @escaping (NoticeButtonConfiguration?) -> Void) {
        guard
            let notificationHandler = AppDelegate.shared.notificationHandler,
            error == nil else {
            completion(nil)
            return
        }

        notificationHandler.arePermissionsGranted { granted in
            let buttonConfiguration = granted
                ? nil
                : NoticeButtonConfiguration(title: L10n.notifyMe, mode: .fill)
            completion(buttonConfiguration)
        }
    }

    fileprivate func alertNotificationsDenied() {
        let alertController = UIAlertController(title: L10n.notificationsDeniedTitle,
                                                message: L10n.notificationsDeniedMessage,
                                                preferredStyle: .alert)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            alertController.addAction(title: L10n.notificationsDeniedAction, style: .default) { _ in
                if #available(iOS 10.0, *) {
                    UIApplication.shared.open(url)
                } else {
                    UIApplication.shared.openURL(url)
                }
            }
        } else {
            alertController.addOkAction()
        }

        present(alertController, animated: true)
    }
}

extension SurveyUnavailableViewController: NoticeViewControllerDelegate {
    func noticeViewControllerDidTapButton(_ viewController: NoticeViewController) {
        Events.Analytics
            .ClickReminderButtonOnLockedTaskPage()
            .send()

        guard let notificationHandler = AppDelegate.shared.notificationHandler else {
            return
        }

        notificationHandler.hasUserBeenAskedAboutPushNotifications { [weak self] asked in
            guard let aSelf = self else {
                return
            }

            if asked {
                aSelf.alertNotificationsDenied()
            } else {
                AppDelegate.shared.requestNotifications { [weak self] granted in
                    if granted {
                        self?.noticeViewController?.hideButton()
                    }
                }
            }
        }
    }
}
