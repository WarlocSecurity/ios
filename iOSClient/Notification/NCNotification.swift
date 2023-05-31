//
//  NCNotification.swift
//  Nextcloud
//
//  Created by Marino Faggiana on 27/01/17.
//  Copyright (c) 2017 Marino Faggiana. All rights reserved.
//
//  Author Marino Faggiana <marino.faggiana@nextcloud.com>
//  Author Henrik Storch <henrik.storch@nextcloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import UIKit
import NextcloudKit
import SwiftyJSON
import JGProgressHUD

class NCNotification: UITableViewController, NCNotificationCellDelegate, NCEmptyDataSetDelegate {

    let appDelegate = UIApplication.shared.delegate as! AppDelegate
    var notifications: [NKNotifications] = []
    var emptyDataSet: NCEmptyDataSet?

    // MARK: - View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("_notifications_", comment: "")
        view.backgroundColor = .systemBackground

        tableView.tableFooterView = UIView()
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 50.0
        tableView.backgroundColor = .systemBackground

        // Empty
        let offset = (self.navigationController?.navigationBar.bounds.height ?? 0) - 20
        emptyDataSet = NCEmptyDataSet(view: tableView, offset: -offset, delegate: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        appDelegate.activeViewController = self
        
        navigationController?.setFileAppreance()

        NotificationCenter.default.addObserver(self, selector: #selector(initialize), name: NSNotification.Name(rawValue: NCGlobal.shared.notificationCenterInitialize), object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        getNetwokingNotification()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: NCGlobal.shared.notificationCenterInitialize), object: nil)
    }

    @objc func viewClose() {
        self.dismiss(animated: true, completion: nil)
    }

    // MARK: - NotificationCenter

    @objc func initialize() {
        getNetwokingNotification()
    }

    // MARK: - Empty

    func emptyDataSetView(_ view: NCEmptyView) {

        view.emptyImage.image = NCUtility.shared.loadImage(named: "bell", color: .gray, size: UIScreen.main.bounds.width)
        view.emptyTitle.text = NSLocalizedString("_no_notification_", comment: "")
        view.emptyDescription.text = ""
    }

    // MARK: - Table

    @objc func reloadDatasource() {
        self.tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        emptyDataSet?.numberOfItemsInSection(notifications.count, section: section)
        return notifications.count
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

        tableView.deselectRow(at: indexPath, animated: true)

        let notification = notifications[indexPath.row]

        if notification.app == "files_sharing" {
            if let metadata = NCManageDatabase.shared.getMetadataFromFileId(notification.objectId) {
                if let filePath = CCUtility.getDirectoryProviderStorageOcId(metadata.ocId, fileNameView: metadata.fileNameView) {
                    do {
                        let attr = try FileManager.default.attributesOfItem(atPath: filePath)
                        let fileSize = attr[FileAttributeKey.size] as! UInt64
                        if fileSize > 0 {
                            NCViewer.shared.view(viewController: self, metadata: metadata, metadatas: [metadata], imageIcon: nil)
                            return
                        }
                    } catch {
                        print("Error: \(error)")
                    }
                }
            }

            let hud = JGProgressHUD()
            hud.indicatorView = JGProgressHUDRingIndicatorView()
            if let indicatorView = hud.indicatorView as? JGProgressHUDRingIndicatorView {
                indicatorView.ringWidth = 1.5
            }
            guard let view = appDelegate.window?.rootViewController?.view else { return }
            hud.show(in: view)

            NextcloudKit.shared.getFileFromFileId(fileId: notification.objectId) { account, file, data, error in
                if let file = file {
                    let isDirectoryE2EE = NCUtility.shared.isDirectoryE2EE(file: file)
                    let metadata = NCManageDatabase.shared.convertFileToMetadata(file, isDirectoryE2EE: isDirectoryE2EE)
                    NCManageDatabase.shared.addMetadata(metadata)

                    let serverUrlFileName = metadata.serverUrl + "/" + metadata.fileName
                    let fileNameLocalPath = CCUtility.getDirectoryProviderStorageOcId(metadata.ocId, fileNameView: metadata.fileNameView)!

                    NextcloudKit.shared.download(serverUrlFileName: serverUrlFileName, fileNameLocalPath: fileNameLocalPath, requestHandler: { _ in
                    }, taskHandler: { _ in
                    }, progressHandler: { progress in
                        hud.progress = Float(progress.fractionCompleted)
                    }) { account, _, _, _, _, _, error in
                        hud.dismiss()
                        if account == self.appDelegate.account && error == .success {
                            NCManageDatabase.shared.addLocalFile(metadata: metadata)
                            NCViewer.shared.view(viewController: self, metadata: metadata, metadatas: [metadata], imageIcon: nil)
                        }
                    }
                } else {
                    hud.dismiss()
                    NCContentPresenter.shared.showError(error: error)
                }
            }
        } else {
            NCApplicationHandle().didSelectNotification(notification, viewController: self)
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = self.tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! NCNotificationCell
        cell.delegate = self

        let notification = notifications[indexPath.row]
        let urlIcon = URL(string: notification.icon)
        var image: UIImage?

        if let urlIcon = urlIcon {
            let pathFileName = String(CCUtility.getDirectoryUserData()) + "/" + urlIcon.deletingPathExtension().lastPathComponent + ".png"
            image = UIImage(contentsOfFile: pathFileName)
        }

        if let image = image {
            cell.icon.image = image.withTintColor(NCBrandColor.shared.brandElement, renderingMode: .alwaysOriginal)
        } else {
            cell.icon.image = NCUtility.shared.loadImage(named: "bell", color: NCBrandColor.shared.brandElement)
        }

        // Avatar
        cell.avatar.isHidden = true
        cell.avatarLeadingMargin.constant = 10
        if let subjectRichParameters = notification.subjectRichParameters,
           let json = JSON(subjectRichParameters).dictionary,
           let user = json["user"]?["id"].stringValue {
            cell.avatar.isHidden = false
            cell.avatarLeadingMargin.constant = 50
            
            let fileName = appDelegate.userBaseUrl + "-" + user + ".png"
            let fileNameLocalPath = String(CCUtility.getDirectoryUserData()) + "/" + fileName
            
            if let image = UIImage(contentsOfFile: fileNameLocalPath) {
                cell.avatar.image = image
            } else if !FileManager.default.fileExists(atPath: fileNameLocalPath) {
                cell.fileUser = user
                NCOperationQueue.shared.downloadAvatar(user: user, dispalyName: json["user"]?["name"].string, fileName: fileName, cell: cell, view: tableView, cellImageView: cell.fileAvatarImageView)
            }
        }

        cell.date.text = DateFormatter.localizedString(from: notification.date as Date, dateStyle: .medium, timeStyle: .medium)
        cell.notification = notification
        cell.date.text = CCUtility.dateDiff(notification.date as Date)
        cell.date.textColor = .gray
        cell.subject.text = notification.subject
        cell.subject.textColor = .label
        cell.message.text = notification.message.replacingOccurrences(of: "<br />", with: "\n")
        cell.message.textColor = .gray

        cell.remove.setImage(UIImage(named: "xmark")!.image(color: .gray, size: 20), for: .normal)

        cell.primary.isEnabled = false
        cell.primary.isHidden = true
        cell.primary.titleLabel?.font = .systemFont(ofSize: 15)
        cell.primary.layer.cornerRadius = 15
        cell.primary.layer.masksToBounds = true
        cell.primary.layer.backgroundColor = NCBrandColor.shared.brandElement.cgColor
        cell.primary.setTitleColor(NCBrandColor.shared.brandText, for: .normal)

        cell.more.isEnabled = false
        cell.more.isHidden = true
        cell.more.titleLabel?.font = .systemFont(ofSize: 15)
        cell.more.layer.cornerRadius = 15
        cell.more.layer.masksToBounds = true
        cell.more.layer.backgroundColor = NCBrandColor.shared.brandElement.cgColor
        cell.more.setTitleColor(NCBrandColor.shared.brandText, for: .normal)

        cell.secondary.isEnabled = false
        cell.secondary.isHidden = true
        cell.secondary.titleLabel?.font = .systemFont(ofSize: 15)
        cell.secondary.layer.cornerRadius = 15
        cell.secondary.layer.masksToBounds = true
        cell.secondary.layer.borderWidth = 1
        cell.secondary.layer.borderColor = UIColor.systemGray.cgColor
        cell.secondary.layer.backgroundColor = UIColor.secondarySystemBackground.cgColor
        cell.secondary.setTitleColor(.black, for: .normal)

        // Action
        if let actions = notification.actions,
           let jsonActions = JSON(actions).array {
            if jsonActions.count == 1 {
                let action = jsonActions[0]

                cell.primary.isEnabled = true
                cell.primary.isHidden = false
                cell.primary.setTitle(action["label"].stringValue, for: .normal)

            } else if jsonActions.count == 2 {

                cell.primary.isEnabled = true
                cell.primary.isHidden = false

                cell.secondary.isEnabled = true
                cell.secondary.isHidden = false

                for action in jsonActions {

                    let label =  action["label"].stringValue
                    let primary = action["primary"].boolValue

                    if primary {
                        cell.primary.setTitle(label, for: .normal)
                    } else {
                        cell.secondary.setTitle(label, for: .normal)
                    }
                }
            } else if jsonActions.count >= 3 {

                cell.more.isEnabled = true
                cell.more.isHidden = false
                cell.more.setTitle("…", for: .normal)
            }

            var buttonWidth = max(cell.primary.intrinsicContentSize.width, cell.secondary.intrinsicContentSize.width)
            buttonWidth += 30
            cell.primaryWidth.constant = buttonWidth
            cell.secondaryWidth.constant = buttonWidth
        }

        return cell
    }

    // MARK: - tap Action

    func tapRemove(with notification: NKNotifications) {

        NextcloudKit.shared.setNotification(serverUrl: nil, idNotification: notification.idNotification , method: "DELETE") { (account, error) in
            if error == .success && account == self.appDelegate.account {

                if let index = self.notifications
                    .firstIndex(where: { $0.idNotification == notification.idNotification })  {
                    self.notifications.remove(at: index)
                }

                self.reloadDatasource()

            } else if error != .success {
                NCContentPresenter.shared.showError(error: error)
            } else {
                print("[Error] The user has been changed during networking process.")
            }
        }
    }

    func tapAction(with notification: NKNotifications, label: String) {
        if notification.app == "spreed",
           let roomToken = notification.objectId.split(separator: "/").first,
           let talkUrl = URL(string: "nextcloudtalk://open-conversation?server=\(appDelegate.urlBase)&user=\(appDelegate.userId)&withRoomToken=\(roomToken)"),
           UIApplication.shared.canOpenURL(talkUrl) {
            UIApplication.shared.open(talkUrl)
        } else if let actions = notification.actions,
                  let jsonActions = JSON(actions).array,
                  let action = jsonActions.first(where: { $0["label"].string == label }) {
                      let serverUrl = action["link"].stringValue
            let method = action["type"].stringValue

            if method == "WEB", let url = action["link"].url {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                return
            }

            NextcloudKit.shared.setNotification(serverUrl: serverUrl, idNotification: 0, method: method) { (account, error) in

                if error == .success && account == self.appDelegate.account {
                    if let index = self.notifications.firstIndex(where: { $0.idNotification == notification.idNotification }) {
                        self.notifications.remove(at: index)
                    }

                    self.reloadDatasource()

                } else if error != .success {
                    NCContentPresenter.shared.showError(error: error)
                } else {
                    print("[Error] The user has been changed during networking process.")
                }
            }
        } // else: Action not found
    }

    func tapMore(with notification: NKNotifications) {
       toggleMenu(notification: notification)
    }

    // MARK: - Load notification networking

    func getNetwokingNotification() {

        NextcloudKit.shared.getNotifications { account, notifications, data, error in

            if error == .success && account == self.appDelegate.account {

                self.notifications.removeAll()
                let sortedListOfNotifications = (notifications! as NSArray).sortedArray(using: [NSSortDescriptor(key: "date", ascending: false)])

                for notification in sortedListOfNotifications {
                    if let icon = (notification as! NKNotifications).icon {
                        NCUtility.shared.convertSVGtoPNGWriteToUserData(svgUrlString: icon, fileName: nil, width: 25, rewrite: false, account: self.appDelegate.account, completion: { _, _ in })
                    }
                    self.notifications.append(notification as! NKNotifications)
                }

                self.reloadDatasource()
            }
        }
    }
}

// MARK: -

class NCNotificationCell: UITableViewCell, NCCellProtocol {

    @IBOutlet weak var icon: UIImageView!
    @IBOutlet weak var avatar: UIImageView!
    @IBOutlet weak var date: UILabel!
    @IBOutlet weak var subject: UILabel!
    @IBOutlet weak var message: UILabel!
    @IBOutlet weak var remove: UIButton!
    @IBOutlet weak var primary: UIButton!
    @IBOutlet weak var secondary: UIButton!
    @IBOutlet weak var more: UIButton!
    @IBOutlet weak var avatarLeadingMargin: NSLayoutConstraint!
    @IBOutlet weak var primaryWidth: NSLayoutConstraint!
    @IBOutlet weak var secondaryWidth: NSLayoutConstraint!

    private var user = ""

    weak var delegate: NCNotificationCellDelegate?
    var notification: NKNotifications?

    var fileAvatarImageView: UIImageView? {
        get { return avatar }
    }
    var fileUser: String? {
        get { return user }
        set { user = newValue ?? "" }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
    }

    @IBAction func touchUpInsideRemove(_ sender: Any) {
        guard let notification = notification else { return }
        delegate?.tapRemove(with: notification)
    }

    @IBAction func touchUpInsidePrimary(_ sender: Any) {
        guard let notification = notification,
                let button = sender as? UIButton,
                let label = button.titleLabel?.text
        else { return }
        delegate?.tapAction(with: notification, label: label)
    }

    @IBAction func touchUpInsideSecondary(_ sender: Any) {
        guard let notification = notification,
                let button = sender as? UIButton,
                let label = button.titleLabel?.text
        else { return }
        delegate?.tapAction(with: notification, label: label)
    }

    @IBAction func touchUpInsideMore(_ sender: Any) {
        guard let notification = notification else { return }
        delegate?.tapMore(with: notification)
    }
}

protocol NCNotificationCellDelegate: AnyObject {
    func tapRemove(with notification: NKNotifications)
    func tapAction(with notification: NKNotifications, label: String)
    func tapMore(with notification: NKNotifications)
}
