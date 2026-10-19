import Foundation
import SwiftUI
import UIKit

/// App 内更新检查：从后台 version.php 获取最新版，下载 IPA 后分享到"文件"。
final class AppUpdateChecker: ObservableObject {
    enum State {
        case idle
        case checking
        case downloading(progress: Double)
        case readyToShare(fileURL: URL)
        case error(message: String)
    }

    @Published var state: State = .idle
    @Published var latestVersion: String = ""
    @Published var latestBuild: Int = 0
    @Published var changelog: String = ""
    @Published var showUpdateAlert = false

    private var downloadURL: String = ""
    private var downloadTask: URLSessionDownloadTask?

    private var currentBuild: Int {
        Int(AppConfiguration.buildNumber) ?? 0
    }

    /// GET version.php，返回 {ok, version, build, download_url, changelog}
    func checkForUpdate() {
        state = .checking
        guard let url = URL(string: "https://mistoto.cc.cd/luiyo/version.php") else {
            state = .error(message: "版本接口地址无效")
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.state = .error(message: "检查失败：" + error.localizedDescription)
                    return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (json["ok"] as? Bool) == true else {
                    self.state = .error(message: "版本接口返回异常")
                    return
                }
                let build = (json["build"] as? Int) ?? 0
                self.latestVersion = (json["version"] as? String) ?? ""
                self.latestBuild = build
                self.changelog = (json["changelog"] as? String) ?? ""
                self.downloadURL = (json["download_url"] as? String) ?? ""
                if build > self.currentBuild, !self.downloadURL.isEmpty {
                    self.state = .idle
                    self.showUpdateAlert = true
                } else {
                    self.state = .error(message: "已是最新版本")
                }
            }
        }.resume()
    }

    /// 下载 IPA，带进度
    func downloadIPA() {
        guard let url = URL(string: downloadURL) else {
            state = .error(message: "下载地址无效")
            return
        }
        state = .downloading(progress: 0)
        downloadTask = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.state = .error(message: "下载失败：" + error.localizedDescription)
                    return
                }
                guard let tempURL else {
                    self.state = .error(message: "下载失败：文件为空")
                    return
                }
                // 移到临时目录并改名
                let fileName = "LUIYo-\(self.latestVersion)-Build(\(self.latestBuild)).ipa"
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: dest)
                do {
                    try FileManager.default.moveItem(at: tempURL, to: dest)
                    self.state = .readyToShare(fileURL: dest)
                    self.presentShareSheet(fileURL: dest)
                } catch {
                    self.state = .error(message: "保存失败：" + error.localizedDescription)
                }
            }
        }
        // 进度监听
        downloadTask?.resume()
        observeProgress()
    }

    private func observeProgress() {
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self, let task = self.downloadTask else { timer.invalidate(); return }
            let progress = task.progress.fractionCompleted
            if case .downloading = self.state {
                self.state = .downloading(progress: progress)
            }
            if progress >= 1.0 { timer.invalidate() }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        state = .idle
    }

    /// 弹出系统分享菜单，可存到"文件"
    private func presentShareSheet(fileURL: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.maxY - 40,
                                        width: 1, height: 1)
        }
        presenter.present(activity, animated: true)
    }
}
