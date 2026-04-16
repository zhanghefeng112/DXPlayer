import UIKit
import DXPlayerSDK
import FSPlayer

class ViewController: UIViewController {

    private var playerContainer: IJKPlayerContainerView!
    private var menuButton: UIButton!
    private var urlInputContainer: UIView!
    private var urlTextView: UITextView!
    private var playButton: UIButton!
    private var isProxyEnabled = false

    // 所有测试按钮（用于 selected/unselected 状态管理）
    private var allTestButtons: [UIButton] = []
    private var selectedButton: UIButton?

    // API 视频+广告测试 URL
    private let videoAdAPIURL = "https://phav.cc/index.php?m=test&a=video_test"
    // 后端 SDK 测试 API（与 Flutter 端相同）
    private let backendSdkAPIURL = "https://baishitong.ai/api/index.php"

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "DXPlayerSDK 代理播放测试"
        view.backgroundColor = .white

        // 打印版本信息
        DXPlayerSDKVersion.printVersionInfo()

        // 配置日志
        DXPlayerLogger.isEnabled = true
        DXPlayerLogger.logLevel = .debug  // 设置为 debug 以查看缩略图预览的详细日志

        // 设置界面
        setupPlayerContainer()
        setupURLInput()
        setupMenuButton()

        // #1803 修復：添加點擊手勢收起鍵盤
        setupTapToDismissKeyboard()

        // 版本号（右下角灰色小字）
        let versionLabel = UILabel()
        versionLabel.text = "2603241800"
        versionLabel.font = .systemFont(ofSize: 10)
        versionLabel.textColor = .gray
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(versionLabel)
        NSLayoutConstraint.activate([
            versionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            versionLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])

        // 启动后默认播放分轨1K
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, let btn = self.allTestButtons.first(where: { $0.title(for: .normal)?.contains("分轨1K") == true }) else { return }
            self.playSplit1K(btn)
        }
    }

    /// #1803 修復：點擊任意區域收起鍵盤
    private func setupTapToDismissKeyboard() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false  // 不阻止其他控件的點擊事件
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func dismissKeyboard() {
        // 收起所有鍵盤（包括 URL 輸入框和彈幕輸入框）
        view.endEditing(true)
        // 同時通知播放器收起彈幕鍵盤
        playerContainer.dismissDanmakuKeyboard()
    }

    private func setupPlayerContainer() {
        playerContainer = IJKPlayerContainerView()
        playerContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playerContainer)

        NSLayoutConstraint.activate([
            playerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            playerContainer.heightAnchor.constraint(equalToConstant: 250)
        ])
    }

    // 测试 URL 源（从此 URL 动态获取带有效 auth_key 的播放地址）
    private let testURLSource = "https://d14.ugujckh.xyz/index.php/index/m3u82"

    // MARK: - TearsOfSteel 5分钟 1K/2K/4K + 对应 VTT
    private let short1KURL = "https://dx-001-office.nhtekmaf.cc/video_thumbnail_package_1k/TearsOfSteel_5min_1k.mp4"
    private let short1KVTT = "https://dx-001-office.nhtekmaf.cc/video_thumbnail_package_1k/output_sprite.vtt"
    private let short2KURL = "https://dx-001-office.nhtekmaf.cc/video_thumbnail_package_2k/TearsOfSteel_5min_2k.mp4"
    private let short2KVTT = "https://dx-001-office.nhtekmaf.cc/video_thumbnail_package_2k/output_sprite.vtt"
    private let short4KURL = "https://dx-001-office.nhtekmaf.cc/video_thumbnail_package_4k/TearsOfSteel_5min_4k.mp4"
    private let short4KVTT = "https://dx-001-office.nhtekmaf.cc/video_thumbnail_package_4k/output_sprite.vtt"

    // MARK: - 音视频分轨 1K/2K/4K
    private let split1KVideo = "https://dx-001-office.nhtekmaf.cc/video_thumbnail_package_1k/video.mp4"
    private let split1KAudio = "https://dx-001-office.nhtekmaf.cc/video_thumbnail_package_1k/audio.mp3"
    private let split2KVideo = "https://dx-001-office.nhtekmaf.cc/video_thumbnail_package_2k/video.mp4"
    private let split2KAudio = "https://dx-001-office.nhtekmaf.cc/video_thumbnail_package_2k/audio.mp3"
    private let split4KVideo = "https://dx-001-office.nhtekmaf.cc/video_thumbnail_package_4k/video.mp4"
    private let split4KAudio = "https://dx-001-office.nhtekmaf.cc/video_thumbnail_package_4k/audio.mp3"

    // 多语言字幕
    private let subtitleTracks: [IJKPlayerContainerView.SubtitleTrack] = [
        .init(lang: "zh", label: "简体中文", url: "https://dx-001-office.nhtekmaf.cc/subtitle/tos.zh.srt"),
        .init(lang: "zh-tc", label: "繁體中文", url: "https://dx-001-office.nhtekmaf.cc/subtitle/tos.zh-tc.srt"),
        .init(lang: "en", label: "English", url: "https://dx-001-office.nhtekmaf.cc/subtitle/tos.en.srt"),
    ]

    // 缓存的动态 URL
    private var cachedEncryptedURL: String?
    private var cachedPlainURL: String?

    private func setupURLInput() {
        // 容器视图
        urlInputContainer = UIView()
        urlInputContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(urlInputContainer)

        // URL 输入框
        urlTextView = UITextView()
        urlTextView.translatesAutoresizingMaskIntoConstraints = false
        urlTextView.font = UIFont.systemFont(ofSize: 14)
        urlTextView.layer.borderColor = UIColor.systemGray4.cgColor
        urlTextView.layer.borderWidth = 1
        urlTextView.layer.cornerRadius = 8
        urlTextView.text = "https://d14.ugujckh.xyz/index.php/index/m3u82"
        urlTextView.textColor = .darkGray
        urlTextView.autocapitalizationType = .none
        urlTextView.autocorrectionType = .no
        urlInputContainer.addSubview(urlTextView)

        // 自动检测提示标签
        let hintLabel = UILabel()
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.text = "🔐 自动检测加密格式"
        hintLabel.font = UIFont.systemFont(ofSize: 12)
        hintLabel.textColor = .systemGray
        urlInputContainer.addSubview(hintLabel)

        // 播放按钮
        playButton = UIButton(type: .system)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.setTitle("播放", for: .normal)
        playButton.setTitleColor(.white, for: .normal)
        playButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 14)
        playButton.backgroundColor = .systemGreen
        playButton.layer.cornerRadius = 8
        playButton.addTarget(self, action: #selector(playInputURL), for: .touchUpInside)
        urlInputContainer.addSubview(playButton)

        // 快捷测试按钮容器
        let quickButtonsContainer = UIView()
        quickButtonsContainer.translatesAutoresizingMaskIntoConstraints = false
        urlInputContainer.addSubview(quickButtonsContainer)

        // 广告+缩略图按钮（baishitong.ai，与 Flutter 端相同 API）
        let backendAdButton = UIButton(type: .system)
        backendAdButton.translatesAutoresizingMaskIntoConstraints = false
        backendAdButton.setTitle("广告+缩略图", for: .normal)
        backendAdButton.setTitleColor(.white, for: .normal)
        backendAdButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        backendAdButton.backgroundColor = .systemPink
        backendAdButton.layer.cornerRadius = 6
        backendAdButton.accessibilityIdentifier = "backendAdButton"
        backendAdButton.addTarget(self, action: #selector(backendAdButtonTapped(_:)), for: .touchUpInside)
        quickButtonsContainer.addSubview(backendAdButton)


        NSLayoutConstraint.activate([
            // 容器
            urlInputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            urlInputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            urlInputContainer.topAnchor.constraint(equalTo: playerContainer.bottomAnchor, constant: 16),
            urlInputContainer.heightAnchor.constraint(equalToConstant: 182),

            // URL 输入框
            urlTextView.leadingAnchor.constraint(equalTo: urlInputContainer.leadingAnchor),
            urlTextView.trailingAnchor.constraint(equalTo: urlInputContainer.trailingAnchor),
            urlTextView.topAnchor.constraint(equalTo: urlInputContainer.topAnchor),
            urlTextView.heightAnchor.constraint(equalToConstant: 44),

            // 提示标签
            hintLabel.leadingAnchor.constraint(equalTo: urlInputContainer.leadingAnchor),
            hintLabel.topAnchor.constraint(equalTo: urlTextView.bottomAnchor, constant: 10),

            // 播放按钮
            playButton.trailingAnchor.constraint(equalTo: urlInputContainer.trailingAnchor),
            playButton.topAnchor.constraint(equalTo: urlTextView.bottomAnchor, constant: 8),
            playButton.widthAnchor.constraint(equalToConstant: 60),
            playButton.heightAnchor.constraint(equalToConstant: 28),

            // 快捷按钮容器
            quickButtonsContainer.leadingAnchor.constraint(equalTo: urlInputContainer.leadingAnchor),
            quickButtonsContainer.trailingAnchor.constraint(equalTo: urlInputContainer.trailingAnchor),
            quickButtonsContainer.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 8),
            quickButtonsContainer.heightAnchor.constraint(equalToConstant: 28),

            // 广告+缩略图按钮
            backendAdButton.leadingAnchor.constraint(equalTo: quickButtonsContainer.leadingAnchor),
            backendAdButton.centerYAnchor.constraint(equalTo: quickButtonsContainer.centerYAnchor),
            backendAdButton.widthAnchor.constraint(equalToConstant: 90),
            backendAdButton.heightAnchor.constraint(equalToConstant: 28),

        ])

        // 第二行测试按钮容器（分辨率测试）
        let resolutionButtonsContainer = UIView()
        resolutionButtonsContainer.translatesAutoresizingMaskIntoConstraints = false
        urlInputContainer.addSubview(resolutionButtonsContainer)

        // 1K 短视频按钮
        let short1KButton = UIButton(type: .system)
        short1KButton.translatesAutoresizingMaskIntoConstraints = false
        short1KButton.setTitle("1K", for: .normal)
        short1KButton.setTitleColor(.white, for: .normal)
        short1KButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        short1KButton.backgroundColor = .systemTeal
        short1KButton.layer.cornerRadius = 6
        short1KButton.addTarget(self, action: #selector(playShort1K), for: .touchUpInside)
        resolutionButtonsContainer.addSubview(short1KButton)

        // 2K 短视频按钮
        let short2KButton = UIButton(type: .system)
        short2KButton.translatesAutoresizingMaskIntoConstraints = false
        short2KButton.setTitle("2K", for: .normal)
        short2KButton.setTitleColor(.white, for: .normal)
        short2KButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        short2KButton.backgroundColor = .systemTeal
        short2KButton.layer.cornerRadius = 6
        short2KButton.addTarget(self, action: #selector(playShort2K), for: .touchUpInside)
        resolutionButtonsContainer.addSubview(short2KButton)

        // 4K 短视频按钮
        let short4KButton = UIButton(type: .system)
        short4KButton.translatesAutoresizingMaskIntoConstraints = false
        short4KButton.setTitle("4K", for: .normal)
        short4KButton.setTitleColor(.white, for: .normal)
        short4KButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        short4KButton.backgroundColor = .systemTeal
        short4KButton.layer.cornerRadius = 6
        short4KButton.addTarget(self, action: #selector(playShort4K), for: .touchUpInside)
        resolutionButtonsContainer.addSubview(short4KButton)

        // 第三行：分轨按钮容器
        let splitButtonsContainer = UIView()
        splitButtonsContainer.translatesAutoresizingMaskIntoConstraints = false
        urlInputContainer.addSubview(splitButtonsContainer)

        // 分轨 1K 按钮
        let split1KButton = UIButton(type: .system)
        split1KButton.translatesAutoresizingMaskIntoConstraints = false
        split1KButton.setTitle("分轨1K", for: .normal)
        split1KButton.setTitleColor(.white, for: .normal)
        split1KButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        split1KButton.backgroundColor = .systemPurple
        split1KButton.layer.cornerRadius = 6
        split1KButton.addTarget(self, action: #selector(playSplit1K), for: .touchUpInside)
        splitButtonsContainer.addSubview(split1KButton)

        // 分轨 2K 按钮
        let split2KButton = UIButton(type: .system)
        split2KButton.translatesAutoresizingMaskIntoConstraints = false
        split2KButton.setTitle("分轨2K", for: .normal)
        split2KButton.setTitleColor(.white, for: .normal)
        split2KButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        split2KButton.backgroundColor = .systemPurple
        split2KButton.layer.cornerRadius = 6
        split2KButton.addTarget(self, action: #selector(playSplit2K), for: .touchUpInside)
        splitButtonsContainer.addSubview(split2KButton)

        // 分轨 4K 按钮
        let split4KButton = UIButton(type: .system)
        split4KButton.translatesAutoresizingMaskIntoConstraints = false
        split4KButton.setTitle("分轨4K", for: .normal)
        split4KButton.setTitleColor(.white, for: .normal)
        split4KButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        split4KButton.backgroundColor = .systemPurple
        split4KButton.layer.cornerRadius = 6
        split4KButton.addTarget(self, action: #selector(playSplit4K), for: .touchUpInside)
        splitButtonsContainer.addSubview(split4KButton)

        NSLayoutConstraint.activate([
            // 分辨率按钮容器
            resolutionButtonsContainer.leadingAnchor.constraint(equalTo: urlInputContainer.leadingAnchor),
            resolutionButtonsContainer.trailingAnchor.constraint(equalTo: urlInputContainer.trailingAnchor),
            resolutionButtonsContainer.topAnchor.constraint(equalTo: quickButtonsContainer.bottomAnchor, constant: 8),
            resolutionButtonsContainer.heightAnchor.constraint(equalToConstant: 28),

            // 短视频按钮
            short1KButton.leadingAnchor.constraint(equalTo: resolutionButtonsContainer.leadingAnchor),
            short1KButton.centerYAnchor.constraint(equalTo: resolutionButtonsContainer.centerYAnchor),
            short1KButton.widthAnchor.constraint(equalToConstant: 40),
            short1KButton.heightAnchor.constraint(equalToConstant: 28),

            short2KButton.leadingAnchor.constraint(equalTo: short1KButton.trailingAnchor, constant: 6),
            short2KButton.centerYAnchor.constraint(equalTo: resolutionButtonsContainer.centerYAnchor),
            short2KButton.widthAnchor.constraint(equalToConstant: 40),
            short2KButton.heightAnchor.constraint(equalToConstant: 28),

            short4KButton.leadingAnchor.constraint(equalTo: short2KButton.trailingAnchor, constant: 6),
            short4KButton.centerYAnchor.constraint(equalTo: resolutionButtonsContainer.centerYAnchor),
            short4KButton.widthAnchor.constraint(equalToConstant: 40),
            short4KButton.heightAnchor.constraint(equalToConstant: 28),

            // 分轨按钮容器
            splitButtonsContainer.leadingAnchor.constraint(equalTo: urlInputContainer.leadingAnchor),
            splitButtonsContainer.trailingAnchor.constraint(equalTo: urlInputContainer.trailingAnchor),
            splitButtonsContainer.topAnchor.constraint(equalTo: resolutionButtonsContainer.bottomAnchor, constant: 8),
            splitButtonsContainer.heightAnchor.constraint(equalToConstant: 28),

            // 分轨按钮
            split1KButton.leadingAnchor.constraint(equalTo: splitButtonsContainer.leadingAnchor),
            split1KButton.centerYAnchor.constraint(equalTo: splitButtonsContainer.centerYAnchor),
            split1KButton.widthAnchor.constraint(equalToConstant: 50),
            split1KButton.heightAnchor.constraint(equalToConstant: 28),

            split2KButton.leadingAnchor.constraint(equalTo: split1KButton.trailingAnchor, constant: 6),
            split2KButton.centerYAnchor.constraint(equalTo: splitButtonsContainer.centerYAnchor),
            split2KButton.widthAnchor.constraint(equalToConstant: 50),
            split2KButton.heightAnchor.constraint(equalToConstant: 28),

            split4KButton.leadingAnchor.constraint(equalTo: split2KButton.trailingAnchor, constant: 6),
            split4KButton.centerYAnchor.constraint(equalTo: splitButtonsContainer.centerYAnchor),
            split4KButton.widthAnchor.constraint(equalToConstant: 50),
            split4KButton.heightAnchor.constraint(equalToConstant: 28),
        ])

        // 注册所有测试按钮
        allTestButtons = [backendAdButton, short1KButton, short2KButton, short4KButton, split1KButton, split2KButton, split4KButton]

        // 默认选中分轨1K
        selectButton(split1KButton)
    }

    /// 设置选中按钮样式（选中=亮色，未选中=灰色）
    private func selectButton(_ button: UIButton) {
        // 恢复所有按钮为未选中状态
        for btn in allTestButtons {
            btn.backgroundColor = UIColor.systemGray4
            btn.setTitleColor(.darkGray, for: .normal)
        }
        // 设置选中按钮
        button.backgroundColor = .systemOrange
        button.setTitleColor(.white, for: .normal)
        selectedButton = button
    }

    @objc private func playDefaultURL() {
        print("🎬 [测试] 播放预设 URL (加密)")
        // 清除缓存，强制重新获取最新 URL
        cachedEncryptedURL = nil
        cachedPlainURL = nil

        // 预设按钮使用加密 URL
        fetchTestURLs { [weak self] encryptedURL, _ in
            guard let self = self, let url = encryptedURL else {
                print("❌ [测试] 无法获取预设 URL")
                return
            }
            DispatchQueue.main.async {
                self.urlTextView.text = url
                self.playerContainer.release()
                self.playerContainer.setVideoConfig(url: url, useProxy: false)
            }
        }
    }

    @objc private func playEncryptedURL() {
        print("🔐 [测试] 播放加密 URL")
        fetchTestURLs { [weak self] encryptedURL, _ in
            guard let self = self, let url = encryptedURL else {
                print("❌ [测试] 无法获取加密 URL")
                return
            }
            DispatchQueue.main.async {
                self.urlTextView.text = url
                self.playerContainer.release()
                self.playerContainer.setVideoConfig(url: url, useProxy: false)
            }
        }
    }

    @objc private func playPlainURL() {
        print("📺 [测试] 播放普通 URL")
        fetchTestURLs { [weak self] _, plainURL in
            guard let self = self, let url = plainURL else {
                print("❌ [测试] 无法获取普通 URL")
                return
            }
            DispatchQueue.main.async {
                self.urlTextView.text = url
                self.playerContainer.release()
                self.playerContainer.setVideoConfig(url: url, useProxy: false)
            }
        }
    }

    @objc private func backendAdButtonTapped(_ sender: UIButton) {
        selectButton(sender)
        testBackendSdkAPI()
    }

    // MARK: - 分辨率测试视频播放方法

    @objc private func playShort1K(_ sender: UIButton) {
        selectButton(sender)
        playTestVideoWithVTT(url: short1KURL, vttUrl: short1KVTT, title: "1K TearsOfSteel")
    }

    @objc private func playShort2K(_ sender: UIButton) {
        selectButton(sender)
        playTestVideoWithVTT(url: short2KURL, vttUrl: short2KVTT, title: "2K TearsOfSteel")
    }

    @objc private func playShort4K(_ sender: UIButton) {
        selectButton(sender)
        playTestVideoWithVTT(url: short4KURL, vttUrl: short4KVTT, title: "4K TearsOfSteel")
    }

    @objc private func playSplit1K(_ sender: UIButton) {
        selectButton(sender)
        playSplitAudioVideo(videoUrl: split1KVideo, audioUrl: split1KAudio, vttUrl: short1KVTT, title: "分轨 1K")
    }

    @objc private func playSplit2K(_ sender: UIButton) {
        selectButton(sender)
        playSplitAudioVideo(videoUrl: split2KVideo, audioUrl: split2KAudio, vttUrl: short2KVTT, title: "分轨 2K")
    }

    @objc private func playSplit4K(_ sender: UIButton) {
        selectButton(sender)
        playSplitAudioVideo(videoUrl: split4KVideo, audioUrl: split4KAudio, vttUrl: short4KVTT, title: "分轨 4K")
    }

    /// 播放测试视频 + VTT 缩略图
    private func playTestVideoWithVTT(url: String, vttUrl: String, title: String) {
        urlTextView.text = url
        playerContainer.release()
        playerContainer.setTitle(title)

        playerContainer.onPlayerReady = { [weak self] in
            guard let self = self else { return }
            if let vtt = URL(string: vttUrl) {
                self.setupThumbnailFromAPI(vttURL: vtt)
            }
        }

        playerContainer.setVideoConfig(url: url, useProxy: false)
    }

    /// 播放测试视频（无缩略图）
    private func playTestVideo(url: String, title: String) {
        urlTextView.text = url
        playerContainer.release()
        playerContainer.setTitle(title)
        playerContainer.setVideoConfig(url: url, useProxy: false)
        playerContainer.play()
    }

    /// 播放分轨视频（视频 + 外部音频）
    private func playSplitAudioVideo(videoUrl: String, audioUrl: String, vttUrl: String, title: String) {
        urlTextView.text = videoUrl
        playerContainer.release()
        playerContainer.setTitle(title)

        playerContainer.onPlayerReady = { [weak self] in
            guard let self = self else { return }
            // 设置外部音频
            self.playerContainer.setExternalAudio(url: audioUrl)
            // 设置多语言字幕
            self.playerContainer.setSubtitleTracks(self.subtitleTracks)
            // 设置缩略图
            if let vtt = URL(string: vttUrl) {
                self.setupThumbnailFromAPI(vttURL: vtt)
            }
        }

        playerContainer.setVideoConfig(url: videoUrl, useProxy: false)
    }

    /// 从源 URL 获取动态测试 URL（带有效 auth_key）
    private func fetchTestURLs(completion: @escaping (String?, String?) -> Void) {
        // 如果已有缓存，直接使用
        if let encrypted = cachedEncryptedURL, let plain = cachedPlainURL {
            completion(encrypted, plain)
            return
        }

        guard let url = URL(string: testURLSource) else {
            completion(nil, nil)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data,
                  let response = String(data: data, encoding: .utf8) else {
                print("❌ [测试] 获取测试 URL 失败: \(error?.localizedDescription ?? "未知错误")")
                completion(nil, nil)
                return
            }

            // 解析响应：两个 URL 用 <br><br> 分隔
            let components = response.components(separatedBy: "<br><br>")
            let encryptedURL = components.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            let plainURL = components.count > 1 ? components[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil

            // 缓存 URL
            self?.cachedEncryptedURL = encryptedURL
            self?.cachedPlainURL = plainURL

            print("✅ [测试] 获取到动态 URL:")
            print("   加密: \(encryptedURL ?? "无")")
            print("   普通: \(plainURL ?? "无")")

            completion(encryptedURL, plainURL)
        }.resume()
    }

    @objc private func playInputURL() {
        guard let urlString = urlTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty else {
            let alert = UIAlertController(title: "错误", message: "请输入播放地址", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
            return
        }

        // 收起键盘
        urlTextView.resignFirstResponder()

        // 停止当前播放
        playerContainer.release()

        print("🎬 [测试] 播放 URL: \(urlString)")
        print("🔐 [测试] 自动检测加密格式")

        // 设置播放器
        playerContainer.onPlayerReady = {
            print("📺 [播放器] 准备好")
        }

        // 自动判断是否需要解密
        playerContainer.setVideoConfig(url: urlString, useProxy: false)
    }

    private func setupMenuButton() {
        menuButton = UIButton(type: .system)
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.setTitle("📋 功能菜单", for: .normal)
        menuButton.setTitleColor(.white, for: .normal)
        menuButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        menuButton.backgroundColor = .systemBlue
        menuButton.layer.cornerRadius = 25
        menuButton.addTarget(self, action: #selector(showMainMenu), for: .touchUpInside)

        view.addSubview(menuButton)

        NSLayoutConstraint.activate([
            menuButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            menuButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            menuButton.widthAnchor.constraint(equalToConstant: 200),
            menuButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    @objc private func showMainMenu() {
        let alert = UIAlertController(title: "功能菜单", message: "选择要测试的功能", preferredStyle: .actionSheet)

        // 1. 代理播放切换
        let proxyTitle = isProxyEnabled ? "⚪️ 关闭代理播放" : "🟢 启用代理播放"
        alert.addAction(UIAlertAction(title: proxyTitle, style: .default) { [weak self] _ in
            self?.toggleProxyMode()
        })

        // 2. 查看代理统计
        alert.addAction(UIAlertAction(title: "📊 查看代理统计", style: .default) { [weak self] _ in
            self?.showProxyStats()
        })

        // 3. 字幕测试
        alert.addAction(UIAlertAction(title: "📝 字幕测试", style: .default) { [weak self] _ in
            self?.testSubtitle()
        })

        // 4. 播放速度
        alert.addAction(UIAlertAction(title: "⚡️ 播放速度", style: .default) { [weak self] _ in
            self?.testPlaybackSpeed()
        })

        // 5. 画面比例
        alert.addAction(UIAlertAction(title: "📐 画面比例", style: .default) { [weak self] _ in
            self?.testAspectRatio()
        })

        // 6. 彈幕測試
        alert.addAction(UIAlertAction(title: "💬 弹幕测试", style: .default) { [weak self] _ in
            self?.testDanmaku()
        })

        // 7. 測試播放錯誤
        alert.addAction(UIAlertAction(title: "❌ 測試播放錯誤", style: .default) { [weak self] _ in
            self?.testPlaybackError()
        })


        alert.addAction(UIAlertAction(title: "取消", style: .cancel))

        present(alert, animated: true)
    }

    @objc private func toggleProxyMode() {
        isProxyEnabled.toggle()

        // 重新播放视频
        playerContainer.release()
        playVideo(useProxy: isProxyEnabled)

        print(isProxyEnabled ? "🟢 切换到代理播放模式" : "⚪️ 切换到直接播放模式")
    }

    @objc private func showProxyStats() {
        let stats = ProxyServer.shared.getProxyStats()
        print(stats)

        let alert = UIAlertController(title: "代理服务器统计", message: stats, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    @objc private func testSubtitle() {
        let alert = UIAlertController(title: "字幕设置", message: "当前: \(playerContainer.getCurrentSubtitleLang() ?? "关闭")", preferredStyle: .actionSheet)

        // 多语言字幕切换
        let currentLang = playerContainer.getCurrentSubtitleLang()
        for track in playerContainer.getSubtitleTracks() {
            let checkmark = track.lang == currentLang ? " ✓" : ""
            alert.addAction(UIAlertAction(title: "\(track.label)\(checkmark)", style: .default) { [weak self] _ in
                self?.playerContainer.switchSubtitle(to: track.lang)
            })
        }

        // 关闭字幕
        let offCheck = currentLang == nil ? " ✓" : ""
        alert.addAction(UIAlertAction(title: "关闭字幕\(offCheck)", style: .default) { [weak self] _ in
            self?.playerContainer.switchSubtitle(to: nil)
        })

        // 分隔线：样式
        alert.addAction(UIAlertAction(title: "── 样式 ──", style: .default, handler: nil))

        alert.addAction(UIAlertAction(title: "大号白色样式", style: .default) { [weak self] _ in
            self?.playerContainer.applySubtitleStylePreset(.largeWhite)
        })

        alert.addAction(UIAlertAction(title: "中号黄色样式", style: .default) { [weak self] _ in
            self?.playerContainer.applySubtitleStylePreset(.mediumYellow)
        })

        alert.addAction(UIAlertAction(title: "小号青色样式", style: .default) { [weak self] _ in
            self?.playerContainer.applySubtitleStylePreset(.smallCyan)
        })

        alert.addAction(UIAlertAction(title: "默认样式", style: .default) { [weak self] _ in
            self?.playerContainer.applySubtitleStylePreset(.defaultStyle)
        })

        // 延迟调整
        alert.addAction(UIAlertAction(title: "字幕延迟 +0.5s", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let d = self.playerContainer.getSubtitleDelay()
            self.playerContainer.setSubtitleDelay(d + 0.5)
        })

        alert.addAction(UIAlertAction(title: "字幕提前 -0.5s", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let d = self.playerContainer.getSubtitleDelay()
            self.playerContainer.setSubtitleDelay(d - 0.5)
        })

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func testPlaybackSpeed() {
        let currentSpeed = playerContainer.getSpeed()
        let speedDesc = playerContainer.getPlaybackSpeedDescription()

        let alert = UIAlertController(
            title: "播放速度",
            message: "当前速度: \(speedDesc)",
            preferredStyle: .actionSheet
        )

        // 添加所有预设速度选项
        let speedOptions: [(String, Float)] = [
            ("0.5x 慢速", 0.5),
            ("0.75x 较慢", 0.75),
            ("1.0x 正常", 1.0),
            ("1.25x 较快", 1.25),
            ("1.5x 快速", 1.5),
            ("2.0x 很快", 2.0),
            ("3.0x 极快", 3.0)
        ]

        for (title, speed) in speedOptions {
            let isCurrentSpeed = abs(speed - currentSpeed) < 0.01
            let actionTitle = isCurrentSpeed ? "\(title) ✓" : title
            let style: UIAlertAction.Style = isCurrentSpeed ? .default : .default

            alert.addAction(UIAlertAction(title: actionTitle, style: style) { [weak self] _ in
                self?.playerContainer.setSpeed(speed)
                print("⚡️ 设置播放速度: \(title)")
            })
        }

        // 切换到下一个速度
        alert.addAction(UIAlertAction(title: "切换到下一个速度", style: .default) { [weak self] _ in
            self?.playerContainer.switchToNextPlaybackSpeed()
            let newSpeed = self?.playerContainer.getPlaybackSpeedDescription() ?? ""
            print("⚡️ 切换速度: \(newSpeed)")
        })

        // 重置为正常速度
        alert.addAction(UIAlertAction(title: "重置为正常速度", style: .destructive) { [weak self] _ in
            self?.playerContainer.resetPlaybackSpeed()
            print("⚡️ 重置速度: 1.0x 正常")
        })

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))

        present(alert, animated: true)
    }

    @objc private func testAspectRatio() {
        let currentMode = playerContainer.getCurrentAspectRatio()
        let modeDesc = playerContainer.getAspectRatioDescription()

        let alert = UIAlertController(
            title: "画面比例",
            message: "当前比例: \(modeDesc)",
            preferredStyle: .actionSheet
        )

        // 添加四個畫面比例选项
        let ratioOptions: [(String, AspectRatioManager.AspectRatioMode)] = [
            ("原始尺寸", .original),
            ("16:9", .ratio16_9),
            ("4:3", .ratio4_3),
            ("鋪滿全屏", .fill)
        ]

        for (title, mode) in ratioOptions {
            let isCurrentMode = mode.rawValue == currentMode.rawValue
            let actionTitle = isCurrentMode ? "\(title) ✓" : title

            alert.addAction(UIAlertAction(title: actionTitle, style: .default) { [weak self] _ in
                self?.playerContainer.setAspectRatio(mode)
                print("📐 设置画面比例: \(title)")
            })
        }

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))

        present(alert, animated: true)
    }

    @objc private func testAd() {
        let alert = UIAlertController(title: "广告测试", message: "选择广告功能测试", preferredStyle: .actionSheet)

        // 测试片头广告 - VIP 用户
        alert.addAction(UIAlertAction(title: "播放片头广告（VIP）", style: .default) { [weak self] _ in
            self?.testPrerollAdVIP()
        })

        // 测试片头广告 - 非 VIP 用户
        alert.addAction(UIAlertAction(title: "播放片头广告（非VIP）", style: .default) { [weak self] _ in
            self?.testPrerollAdNonVIP()
        })

        // 测试暂停广告 - 网络图片
        alert.addAction(UIAlertAction(title: "显示暂停广告（网络图片）", style: .default) { [weak self] _ in
            self?.testPauseAdURL()
        })

        // 测试暂停广告 - 本地图片
        alert.addAction(UIAlertAction(title: "显示暂停广告（本地图片）", style: .default) { [weak self] _ in
            self?.testPauseAdLocal()
        })

        // 隐藏暂停广告
        alert.addAction(UIAlertAction(title: "隐藏暂停广告", style: .destructive) { [weak self] _ in
            self?.playerContainer.hidePauseAd()
            print("❌ 已隐藏暂停广告")
        })

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))

        present(alert, animated: true)
    }

    @objc private func testDanmaku() {
        let isEnabled = playerContainer.isDanmakuEnabled
        let statusText = isEnabled ? "已启用 ✓" : "已禁用"

        let alert = UIAlertController(
            title: "弹幕测试",
            message: "当前状态: \(statusText)",
            preferredStyle: .actionSheet
        )

        // 发送测试弹幕
        alert.addAction(UIAlertAction(title: "发送测试弹幕", style: .default) { [weak self] _ in
            guard let self = self else { return }

            let testMessages = [
                "这是一条测试弹幕 💬",
                "弹幕功能正在运行 ✨",
                "DXPlayerSDK 测试 🎉",
                "Hello World! 👋",
                "测试成功 ✅"
            ]

            let randomMessage = testMessages.randomElement()!
            self.playerContainer.sendDanmaku(text: randomMessage) { result in
                switch result {
                case .success:
                    print("✅ [弹幕测试] 发送成功: \(randomMessage)")
                case .failure(let error):
                    print("❌ [弹幕测试] 发送失败: \(error.localizedDescription)")
                }
            }
        })

        // 切换弹幕开关
        let toggleTitle = isEnabled ? "关闭弹幕" : "开启弹幕"
        alert.addAction(UIAlertAction(title: toggleTitle, style: .default) { [weak self] _ in
            guard let self = self else { return }
            let newState = !self.playerContainer.isDanmakuEnabled
            self.playerContainer.setDanmakuEnabled(newState)
            print(newState ? "✅ [弹幕测试] 弹幕已开启" : "❌ [弹幕测试] 弹幕已关闭")
        })

        // 显示弹幕设置
        alert.addAction(UIAlertAction(title: "显示弹幕设置", style: .default) { [weak self] _ in
            // 弹幕设置面板会通过 DanmakuControlView 的设置按钮显示
            // 这里我们可以直接调用，但需要访问 DanmakuControlView
            print("💡 [弹幕测试] 请点击播放器底部的设置按钮打开弹幕设置面板")

            // 显示提示
            let infoAlert = UIAlertController(
                title: "弹幕设置",
                message: "请点击播放器底部的齿轮按钮 ⚙️ 打开弹幕设置面板",
                preferredStyle: .alert
            )
            infoAlert.addAction(UIAlertAction(title: "知道了", style: .default))
            self?.present(infoAlert, animated: true)
        })

        // 清空所有弹幕
        alert.addAction(UIAlertAction(title: "清空所有弹幕", style: .destructive) { [weak self] _ in
            self?.playerContainer.clearDanmaku()
            print("🧹 [弹幕测试] 已清空所有弹幕")
        })

        // 批量发送测试
        alert.addAction(UIAlertAction(title: "批量发送测试（10条）", style: .default) { [weak self] _ in
            guard let self = self else { return }

            let testMessages = [
                "精彩！🎉", "太棒了！👏", "哈哈哈😄", "666 ✨",
                "主播加油！💪", "这段好看👀", "来了来了🔥", "刷起来🌟",
                "支持支持❤️", "真不错👍"
            ]

            for (index, message) in testMessages.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.5) {
                    self.playerContainer.sendDanmaku(text: message) { result in
                        if case .success = result {
                            print("✅ [批量测试] 第 \(index + 1)/10 条发送成功")
                        }
                    }
                }
            }

            print("🚀 [弹幕测试] 开始批量发送 10 条测试弹幕")
        })

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))

        present(alert, animated: true)
    }

    @objc private func testThumbnail() {
        // 直接播放 Big Buck Bunny + VTT/Sprite
        playBigBuckBunnyWithSprites()
    }

    // MARK: - 广告测试方法

    /// Mock 测试广告 - 自动显示
    private func showMockPrerollAd() {
        print("📺 [Mock 广告] 创建测试片头广告...")

        // 使用一个短视频作为广告（Big Buck Bunny 预告片）
        guard let adVideoURL = URL(string: "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4") else {
            print("❌ [Mock 广告] 无法创建广告视频 URL")
            return
        }

        // 配置片头广告 - VIP 模式，可以跳过
        var config = PrerollAdConfig(
            videoURL: adVideoURL,
            duration: 15, // 15 秒广告
            isVIP: true, // VIP 用户，显示跳过按钮
            detailURL: URL(string: "https://www.example.com/ad-campaign")
        )

        config.onCompleted = { [weak self] in
            print("✅ [Mock 广告] 广告播放完成，恢复主视频")

            // 廣告結束後加載字幕
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                print("⏰ 开始加载字幕...")
                self?.loadSintelSubtitleMock()
            }
        }

        config.onSkipped = { reason in
            switch reason {
            case .vipSkip:
                print("⏩ [Mock 广告] VIP 用户点击跳过按钮")
            case .detailClick:
                print("🔗 [Mock 广告] 用户点击了解详情")
            case .completed:
                print("✅ [Mock 广告] 广告自然播放完成")
            }
        }

        config.onDetailClicked = { url in
            print("🔗 [Mock 广告] 用户点击广告详情: \(url)")
            // 在这里可以打开浏览器或应用内 WebView
            if let url = URL(string: "https://www.example.com/ad-campaign") {
                UIApplication.shared.open(url)
            }
        }

        config.onError = { error in
            print("❌ [Mock 广告] 播放错误: \(error.localizedDescription)")
        }

        // 显示片头广告
        playerContainer.showPrerollAd(config: config)

        print("📺 [Mock 广告] 片头广告已启动")
        print("   - 视频 URL: \(adVideoURL)")
        print("   - 时长: 15 秒")
        print("   - VIP 模式: 可跳过")
        print("   - 详情链接: https://www.example.com/ad-campaign")
    }

    /// 测试片头广告 - VIP 用户
    private func testPrerollAdVIP() {
        print("📺 [广告测试] 开始测试片头广告（VIP）")

        // 使用短视频作为广告视频
        guard let adVideoURL = URL(string: "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4") else {
            return
        }

        // 配置片头广告
        var config = PrerollAdConfig(
            videoURL: adVideoURL,
            duration: 15, // 15秒广告
            isVIP: true, // VIP 用户可跳过
            detailURL: URL(string: "https://www.example.com/ad-detail")
        )

        config.onCompleted = {
            print("✅ [广告] 片头广告播放完成")
        }

        config.onSkipped = { reason in
            print("⏩ [广告] 片头广告已跳过，原因: \(reason)")
        }

        config.onDetailClicked = { url in
            print("🔗 [广告] 点击了解详情: \(url)")
        }

        config.onError = { error in
            print("❌ [广告] 错误: \(error.localizedDescription)")
        }

        // 显示片头广告
        playerContainer.showPrerollAd(config: config)
    }

    /// 测试片头广告 - 非 VIP 用户
    private func testPrerollAdNonVIP() {
        print("📺 [广告测试] 开始测试片头广告（非VIP）")

        // 使用短视频作为广告视频
        guard let adVideoURL = URL(string: "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4") else {
            return
        }

        // 配置片头广告
        var config = PrerollAdConfig(
            videoURL: adVideoURL,
            duration: 20, // 20秒广告
            isVIP: false, // 非 VIP 用户不可跳过
            detailURL: URL(string: "https://www.example.com/ad-detail")
        )

        config.onCompleted = {
            print("✅ [广告] 片头广告播放完成")
        }

        config.onSkipped = { reason in
            print("⏩ [广告] 片头广告已跳过，原因: \(reason)")
        }

        config.onDetailClicked = { url in
            print("🔗 [广告] 点击了解详情: \(url)")
        }

        config.onError = { error in
            print("❌ [广告] 错误: \(error.localizedDescription)")
        }

        // 显示片头广告
        playerContainer.showPrerollAd(config: config)
    }

    /// 测试暂停广告 - 网络图片
    private func testPauseAdURL() {
        print("🖼️ [广告测试] 开始测试暂停广告（网络图片）")

        // 使用测试图片 URL
        guard let imageURL = URL(string: "https://via.placeholder.com/300x200.png?text=Pause+Ad") else {
            return
        }

        // 配置暂停广告
        var config = PauseAdConfig(
            imageSource: .url(imageURL),
            detailURL: URL(string: "https://www.example.com/pause-ad-detail"),
            size: CGSize(width: 300, height: 200)
        )

        config.onShown = {
            print("✅ [广告] 暂停广告已显示")
        }

        config.onHidden = {
            print("👋 [广告] 暂停广告已隐藏")
        }

        config.onClicked = { url in
            if let url = url {
                print("🔗 [广告] 暂停广告被点击: \(url)")
            }
        }

        config.onClosed = {
            print("❌ [广告] 暂停广告被关闭")
        }

        config.onError = { error in
            print("❌ [广告] 错误: \(error.localizedDescription)")
        }

        // 显示暂停广告
        playerContainer.showPauseAd(config: config)
    }

    /// 测试暂停广告 - 本地图片
    private func testPauseAdLocal() {
        print("🖼️ [广告测试] 开始测试暂停广告（本地图片）")

        // 创建简单的占位图片
        let size = CGSize(width: 300, height: 200)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }

        let context = UIGraphicsGetCurrentContext()!

        // 绘制渐变背景
        context.setFillColor(UIColor.systemBlue.withAlphaComponent(0.8).cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        // 绘制文字
        let text = "暂停广告\nPause Ad"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 24),
            .foregroundColor: UIColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)

        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            print("❌ [广告测试] 无法创建图片")
            return
        }

        // 配置暂停广告
        var config = PauseAdConfig(
            imageSource: .image(image),
            detailURL: URL(string: "https://www.example.com/pause-ad-detail"),
            size: CGSize(width: 300, height: 200)
        )

        config.onShown = {
            print("✅ [广告] 暂停广告已显示")
        }

        config.onHidden = {
            print("👋 [广告] 暂停广告已隐藏")
        }

        config.onClicked = { url in
            if let url = url {
                print("🔗 [广告] 暂停广告被点击: \(url)")
            }
        }

        config.onClosed = {
            print("❌ [广告] 暂停广告被关闭")
        }

        config.onError = { error in
            print("❌ [广告] 错误: \(error.localizedDescription)")
        }

        // 显示暂停广告
        playerContainer.showPauseAd(config: config)
    }

    private func loadTestSubtitle() {
        // 使用 Sintel 影片的官方字幕 URL
        let subtitleURL = URL(string: "https://durian.blender.org/wp-content/content/subtitles/sintel_en.srt")!

        print("📝 [测试字幕] 尝试加载网络字幕: \(subtitleURL)")

        let success = playerContainer.loadSubtitle(url: subtitleURL)
        print("📝 [测试字幕] loadSubtitle 返回值: \(success)")

        if success {
            print("✅ 网络字幕加载成功")
            // 应用样式
            // 注意：FSPlayer 使用 ASS 格式的 RGBA，其中 alpha=0 表示不透明，alpha=FF 表示透明
            playerContainer.configureSubtitleStyle(
                scale: 1.5,
                bottomMargin: 0.1,
                fontName: "Helvetica-Bold",
                textColor: 0xFFFFFF00,      // 白色，alpha=0 不透明
                outlineWidth: 3.0,
                outlineColor: 0x00000000    // 黑色边框，alpha=0 不透明
            )
        } else {
            print("❌ 网络字幕加载失败，尝试本地字幕")
            loadLocalTestSubtitle()
        }
    }

    private func loadLocalTestSubtitle() {
        // 获取当前播放时间，从当前位置开始显示字幕
        let currentTime = playerContainer.getPosition()
        let startSec = Int(currentTime)

        // 格式化时间为 SRT 格式
        func formatTime(_ seconds: Int) -> String {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            let s = seconds % 60
            return String(format: "%02d:%02d:%02d,000", h, m, s)
        }

        // 创建从当前时间开始的测试字幕
        let srtContent = """
1
\(formatTime(startSec)) --> \(formatTime(startSec + 5))
*** TEST SUBTITLE LINE 1 ***

2
\(formatTime(startSec + 5)) --> \(formatTime(startSec + 10))
THIS IS LINE 2 - YELLOW TEXT

3
\(formatTime(startSec + 10)) --> \(formatTime(startSec + 15))
LINE 3 - YOU SHOULD SEE THIS

4
\(formatTime(startSec + 15)) --> \(formatTime(startSec + 30))
LINE 4 - SUBTITLE TEST SUCCESS
"""

        // 保存到临时文件
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_subtitle_\(Int(Date().timeIntervalSince1970)).srt")

        do {
            try srtContent.write(to: tempURL, atomically: true, encoding: .utf8)

            // 先配置字体样式
            // 注意：FSPlayer 使用 ASS 格式的 RGBA，其中 alpha=0 表示不透明，alpha=FF 表示透明
            playerContainer.configureSubtitleStyle(
                scale: 2.5,                      // 超大字号
                bottomMargin: 0.2,               // 离底部很远
                fontName: "Helvetica-Bold",      // 粗体
                textColor: 0xFFFF0000,           // 黄色，alpha=0 不透明
                outlineWidth: 5.0,               // 超粗边框
                outlineColor: 0x00000000         // 黑色边框，alpha=0 不透明
            )
            print("🎨 [测试字幕] 已配置超大黄色字体样式")

            print("📝 [测试字幕] 字幕文件内容:")
            print(srtContent)
            print("📝 [测试字幕] 文件路径: \(tempURL.path)")

            let success = playerContainer.loadSubtitle(url: tempURL)
            print("📝 [测试字幕] loadSubtitle 返回值: \(success)")
            if success {
                print("✅ 测试字幕加载成功: \(tempURL.path)")

                // 加载后重新应用样式确保生效
                playerContainer.configureSubtitleStyle(
                    scale: 2.5,
                    bottomMargin: 0.15,
                    fontName: "Helvetica-Bold",
                    textColor: 0xFFFF0000,       // 黄色，alpha=0 不透明
                    outlineWidth: 4.0,
                    outlineColor: 0x00000000     // 黑色边框，alpha=0 不透明
                )
                print("🎨 [测试字幕] 重新应用字幕样式")

                // 註釋：不再顯示字幕加載提示
                // let resultAlert = UIAlertController(
                //     title: "字幕加载成功",
                //     message: "测试字幕已加载，播放视频时会看到字幕显示",
                //     preferredStyle: .alert
                // )
                // resultAlert.addAction(UIAlertAction(title: "确定", style: .default))
                // present(resultAlert, animated: true)
            } else {
                print("❌ 测试字幕加载失败")
            }
        } catch {
            print("❌ 创建测试字幕文件失败: \(error)")
        }
    }

    private func playVideo(useProxy: Bool) {
        // 测试视频 URL（自动检测是否加密）
        let testVideoURL = "https://d14.ugujckh.xyz/index.php/index/m3u82"

        // 設置播放器準備好後的回調
        playerContainer.onPlayerReady = { [weak self] in
            print("📺 [播放器] 準備好")
        }

        // 初始化播放器（自动判断是否需要解密）
        playerContainer.setVideoConfig(url: testVideoURL, useProxy: useProxy)

        print("🔐 [測試] 智能播放（自动检测加密格式）")
    }

    /// 測試播放錯誤狀態
    private func testPlaybackError() {
        print("❌ [測試] 開始測試播放錯誤狀態")

        // 使用一個不存在的 URL 來觸發播放錯誤
        let invalidURL = "http://invalid-url-that-does-not-exist.com/video.mp4"

        playerContainer.release()
        playerContainer.setVideoConfig(url: invalidURL, useProxy: false)
        playerContainer.play()

        print("❌ [測試] 已嘗試播放無效 URL: \(invalidURL)")
        print("❌ [測試] 預期會觸發播放錯誤並顯示錯誤提示")
    }

    // MARK: - API 视频+广告测试

    /// 从 API 获取视频+广告数据并播放
    private func testVideoAdAPI() {
        print("🎬 [API 广告] 开始调用 API: \(videoAdAPIURL)")

        guard let url = URL(string: videoAdAPIURL),
              let sourceURL = URL(string: testURLSource) else {
            print("❌ [API 广告] URL 无效")
            return
        }

        // 并行获取：1) API 广告数据 2) 可用的广告视频 URL（从 testURLSource）
        var apiData: VideoAdData?
        var adVideoWorkingURL: String?  // testURLSource 返回的 URL（路径与 ad_video 一致）
        let group = DispatchGroup()

        // 1) 获取 API 广告数据
        group.enter()
        URLSession.shared.dataTask(with: url) { data, _, error in
            defer { group.leave() }
            guard let data = data else {
                print("❌ [API 广告] 请求失败: \(error?.localizedDescription ?? "无数据")")
                return
            }
            do {
                let response = try JSONDecoder().decode(VideoAdResponse.self, from: data)
                apiData = response.data
                print("✅ [API 广告] 解析成功")
            } catch {
                print("❌ [API 广告] JSON 解析失败: \(error)")
            }
        }.resume()

        // 2) 获取可用的广告视频 URL
        //    testURLSource 返回的 hls.isidum.cn URL 路径与 API 的 ad_video 一致
        group.enter()
        URLSession.shared.dataTask(with: sourceURL) { data, _, error in
            defer { group.leave() }
            guard let data = data, let text = String(data: data, encoding: .utf8) else {
                print("❌ [API 广告] 获取广告视频 URL 失败")
                return
            }
            let components = text.components(separatedBy: "<br><br>")
            adVideoWorkingURL = components.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            print("✅ [API 广告] 获取到广告视频 URL: \(adVideoWorkingURL?.prefix(80) ?? "无")...")
        }.resume()

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }

            guard let data = apiData else {
                let alert = UIAlertController(title: "错误", message: "API 数据获取失败", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "确定", style: .default))
                self.present(alert, animated: true)
                return
            }

            self.playVideoWithAPIAds(data, adVideoWorkingURL: adVideoWorkingURL)
        }
    }

    /// 使用 API 返回的数据播放视频+广告（新版 ads 架构）
    private func playVideoWithAPIAds(_ data: VideoAdData, adVideoWorkingURL: String?) {
        print("🎬 [API 广告] 开始配置播放（新架构）")

        // 释放当前播放器
        playerContainer.release()

        // 使用 API 返回的视频 URL
        let mainVideoURL = data.videoUrl

        // 构建暂停广告配置
        let pauseAdConfig = buildPauseAdConfig(from: data)

        // 构建中插广告配置列表
        let midrollConfigs = buildMidrollAdConfigs(from: data)

        // 准备片头广告
        let preroll = data.prerollAd

        // 如果片头广告是视频格式，需要先解密
        if let preroll = preroll, preroll.format == "video", let src = preroll.src {
            let adURLString = src.hasPrefix("/") ? "https://new.wbsatn.cn\(src)" : src
            // 优先用 adVideoWorkingURL（已有正确 auth_key）
            let urlToDecrypt = adVideoWorkingURL ?? adURLString
            guard let adVideoURL = URL(string: urlToDecrypt) else {
                startPlaybackWithAds(mainVideoURL: mainVideoURL, preroll: preroll, prerollVideoURL: nil, pauseAdConfig: pauseAdConfig, midrollConfigs: midrollConfigs, thumbnailInfo: data.thumbnail)
                return
            }

            Decryptor.shared.smartDecrypt(from: adVideoURL) { [weak self] result in
                guard let self = self else { return }
                var resolvedURL: URL?
                switch result {
                case .success(let info):
                    if info.isPlainM3u8, let redirectURL = info.redirectURL {
                        resolvedURL = redirectURL
                    } else if let content = info.decryptedContent {
                        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ad-\(Int(Date().timeIntervalSince1970)).m3u8")
                        try? content.write(to: tmp, atomically: true, encoding: .utf8)
                        resolvedURL = tmp
                    }
                case .failure(let error):
                    print("⚠️ [API 广告] 片头视频解密失败: \(error.localizedDescription)")
                }
                DispatchQueue.main.async {
                    self.startPlaybackWithAds(mainVideoURL: mainVideoURL, preroll: preroll, prerollVideoURL: resolvedURL, pauseAdConfig: pauseAdConfig, midrollConfigs: midrollConfigs, thumbnailInfo: data.thumbnail)
                }
            }
        } else {
            // 非视频格式（gif/image）或无片头广告
            startPlaybackWithAds(mainVideoURL: mainVideoURL, preroll: preroll, prerollVideoURL: nil, pauseAdConfig: pauseAdConfig, midrollConfigs: midrollConfigs, thumbnailInfo: data.thumbnail)
        }
    }

    /// 构建暂停广告配置（从新架构 pauseAd 取，支持 image/gif/video）
    private func buildPauseAdConfig(from data: VideoAdData) -> PauseAdConfig? {
        guard let ad = data.pauseAd, let src = ad.src else { return nil }

        let urlString = src.hasPrefix("/") ? "https://new.wbsatn.cn\(src)" : src
        guard let adURL = URL(string: urlString) else { return nil }

        let imageSource: ImageSource
        if ad.format == "video" {
            // 视频格式：需要先解密，这里先存原始 URL，后续异步解密
            imageSource = .video(adURL)
        } else {
            imageSource = .url(adURL)
        }

        var config = PauseAdConfig(
            imageSource: imageSource,
            detailURL: nil,
            size: CGSize(width: 300, height: 200)
        )

        config.onShown = { print("✅ [暂停广告] 已显示 (format=\(ad.format ?? "unknown"))") }
        config.onHidden = { print("👋 [暂停广告] 已隐藏") }
        config.onClicked = { url in
            if let url = url {
                print("🔗 [暂停广告] 被点击: \(url)")
                UIApplication.shared.open(url)
            }
        }
        config.onClosed = { print("❌ [暂停广告] 被关闭") }

        print("✅ [广告] 暂停广告已配置: format=\(ad.format ?? "unknown") url=\(urlString.prefix(80))")
        return config
    }

    /// 异步解密暂停广告视频 URL，解密完成后更新配置
    private func preloadPauseAdVideo(url: URL, completion: @escaping (URL?) -> Void) {
        Decryptor.shared.smartDecrypt(from: url) { result in
            var resolvedURL: URL?
            switch result {
            case .success(let info):
                if info.isPlainM3u8, let redirectURL = info.redirectURL {
                    resolvedURL = redirectURL
                } else if let content = info.decryptedContent {
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pause-ad-\(Int(Date().timeIntervalSince1970)).m3u8")
                    try? content.write(to: tmp, atomically: true, encoding: .utf8)
                    resolvedURL = tmp
                }
            case .failure(let error):
                print("⚠️ [暂停广告] 视频解密失败: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                completion(resolvedURL)
            }
        }
    }

    /// 构建中插广告配置列表
    private func buildMidrollAdConfigs(from data: VideoAdData) -> [MidrollAdConfig] {
        return data.midrollAds.compactMap { ad -> MidrollAdConfig? in
            guard let at = ad.at else { return nil }
            return MidrollAdConfig(
                triggerTime: at,
                format: ad.format ?? "image",
                src: ad.src,
                duration: TimeInterval(ad.duration ?? 15),
                canSkip: ad.skip ?? true,
                allowSkipTime: ad.allowSkipTime ?? 0,
                onShown: { print("📺 [中插广告] 已显示 ad_id=\(ad.adId ?? 0)") },
                onCompleted: { print("✅ [中插广告] 已结束 ad_id=\(ad.adId ?? 0)") }
            )
        }
    }

    /// 启动播放：配置所有广告，加载主视频
    private func startPlaybackWithAds(
        mainVideoURL: String,
        preroll: AdItem?,
        prerollVideoURL: URL?,
        pauseAdConfig: PauseAdConfig?,
        midrollConfigs: [MidrollAdConfig],
        thumbnailInfo: ThumbnailInfo? = nil
    ) {
        urlTextView.text = mainVideoURL
        playerContainer.setTitle("🎬 API 视频+广告")

        playerContainer.onPlayerReady = { [weak self] in
            guard let self = self else { return }
            print("📺 [广告] 播放器就绪，开始配置广告")

            // 1. 暂停广告
            if var pauseConfig = pauseAdConfig {
                // 如果是视频格式，先解密再配置
                if case .video(let rawURL) = pauseConfig.imageSource {
                    print("🔄 [暂停广告] 开始解密视频 URL: \(rawURL.absoluteString.prefix(80))...")
                    self.preloadPauseAdVideo(url: rawURL) { resolvedURL in
                        if let resolvedURL = resolvedURL {
                            pauseConfig.imageSource = .video(resolvedURL)
                            self.playerContainer.configurePauseAd(config: pauseConfig)
                            print("✅ [暂停广告] 视频解密完成，已配置: \(resolvedURL)")
                        } else {
                            // 解密失败，尝试直接用原始 URL（可能是普通 m3u8）
                            print("⚠️ [暂停广告] 视频解密失败，尝试直接使用原始 URL")
                            self.playerContainer.configurePauseAd(config: pauseConfig)
                        }
                    }
                } else {
                    self.playerContainer.configurePauseAd(config: pauseConfig)
                    print("✅ [暂停广告] 图片格式已配置")
                }
            } else {
                print("⚠️ [暂停广告] 无暂停广告配置（pauseAd 为空或格式不支持）")
            }

            // 2. 中插广告
            for config in midrollConfigs {
                self.playerContainer.addMidrollAd(config: config)
            }

            // 3. 片头广告
            if let preroll = preroll {
                if preroll.format == "video", let adURL = prerollVideoURL {
                    // 视频格式片头广告
                    self.showAPIPrerollAd(adURL: adURL, adDetailURL: nil, duration: TimeInterval(preroll.duration ?? 15), canSkip: preroll.skip ?? true, allowSkipTime: preroll.allowSkipTime ?? 0)
                } else if let src = preroll.src {
                    // 图片/GIF 格式片头广告 → 用中插广告覆盖层实现（全屏+倒计时）
                    let imgSrc = src.hasPrefix("/") ? "https://new.wbsatn.cn\(src)" : src
                    let config = MidrollAdConfig(
                        triggerTime: 0,
                        format: preroll.format ?? "image",
                        src: imgSrc,
                        duration: TimeInterval(preroll.duration ?? 15),
                        canSkip: preroll.skip ?? true,
                        allowSkipTime: preroll.allowSkipTime ?? 0,
                        onCompleted: { print("✅ [片头广告] GIF/图片广告结束") }
                    )
                    // 直接触发（不等播放到 0 秒）
                    self.playerContainer.addMidrollAd(config: config)
                    // 暂停主视频，让中插广告立即触发
                }
            }

            // 4. 缩略图
            if let thumbnail = thumbnailInfo, let vttURL = URL(string: thumbnail.vttUrl) {
                self.setupThumbnailFromAPI(vttURL: vttURL)
            }
        }

        playerContainer.setVideoConfig(url: mainVideoURL, useProxy: false)
    }

    /// 从 API 返回的 VTT URL 设置缩略图预览
    private func setupThumbnailFromAPI(vttURL: URL) {
        print("🖼️ [缩略图] 从 API 加载 VTT: \(vttURL)")

        URLSession.shared.dataTask(with: vttURL) { [weak self] data, _, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ [缩略图] VTT 下载失败: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                print("❌ [缩略图] VTT 无数据")
                return
            }

            let parser = ThumbnailSpriteParser()
            let success = parser.parse(data: data, baseURL: vttURL.deletingLastPathComponent())

            if success {
                print("✅ [缩略图] VTT 解析成功，共 \(parser.metadataItems.count) 个缩略图")
                DispatchQueue.main.async {
                    self.playerContainer.setThumbnailParser(parser)
                }
            } else {
                print("❌ [缩略图] VTT 解析失败")
            }
        }.resume()
    }

    /// 显示 API 片头广告
    private func showAPIPrerollAd(adURL: URL, adDetailURL: URL?, duration: TimeInterval = 15, canSkip: Bool = true, allowSkipTime: Int = 0) {
        print("📺 [API 广告] 显示片头广告: \(adURL)")

        var prerollConfig = PrerollAdConfig(
            videoURL: adURL,
            duration: duration,
            isVIP: true,
            detailURL: adDetailURL,
            canSkip: canSkip,
            allowSkipTime: allowSkipTime
        )

        prerollConfig.onCompleted = {
            print("✅ [API 片头广告] 播放完成")
        }

        prerollConfig.onSkipped = { reason in
            print("⏩ [API 片头广告] 已跳过，原因: \(reason)")
        }

        prerollConfig.onDetailClicked = { url in
            print("🔗 [API 片头广告] 点击详情: \(url)")
            UIApplication.shared.open(url)
        }

        prerollConfig.onError = { error in
            print("❌ [API 片头广告] 错误: \(error.localizedDescription)")
        }

        playerContainer.showPrerollAd(config: prerollConfig)
    }

    // MARK: - 后端 SDK API 测试（baishitong.ai，与 Flutter 端相同）

    /// 从后端 SDK API 获取视频+广告+缩略图数据并播放
    private func testBackendSdkAPI() {
        print("🎬 [后端SDK] 开始调用 API: \(backendSdkAPIURL)")

        guard let url = URL(string: backendSdkAPIURL) else {
            print("❌ [后端SDK] URL 无效")
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }

            guard let data = data else {
                print("❌ [后端SDK] 请求失败: \(error?.localizedDescription ?? "无数据")")
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: "错误", message: "后端 SDK API 请求失败", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "确定", style: .default))
                    self.present(alert, animated: true)
                }
                return
            }

            do {
                let response = try JSONDecoder().decode(VideoAdResponse.self, from: data)
                print("✅ [后端SDK] 解析成功, videoUrl=\(response.data.videoUrl.prefix(60))..., isEncryption=\(response.data.isEncryption ?? -1)")
                DispatchQueue.main.async {
                    self.playVideoWithBackendSdkData(response.data)
                }
            } catch {
                print("❌ [后端SDK] JSON 解析失败: \(error)")
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: "错误", message: "JSON 解析失败: \(error.localizedDescription)", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "确定", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }.resume()
    }

    /// 使用后端 SDK 返回的数据播放视频+广告+缩略图（复用新架构）
    private func playVideoWithBackendSdkData(_ data: VideoAdData) {
        print("🎬 [后端SDK] 开始配置播放（复用新架构）")
        playVideoWithAPIAds(data, adVideoWorkingURL: nil)
    }

    /// Big Buck Bunny + VTT/Sprite 测试
    private func playBigBuckBunnyWithSprites() {
        // Big Buck Bunny 视频 URL（约10分钟）
        let videoURL = "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"

        // 获取本地 VTT 和 Sprite 文件路径
        guard let vttURL = Bundle.main.url(forResource: "thumbs", withExtension: "vtt"),
              let spriteURL = Bundle.main.url(forResource: "sprite", withExtension: "jpg") else {
            print("❌ 找不到 VTT 或 Sprite 文件")
            let alert = UIAlertController(
                title: "错误",
                message: "找不到测试资源文件\n请确保 thumbs.vtt 和 sprite.jpg 已添加到项目中",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
            return
        }

        print("🎬 [Big Buck Bunny] 开始播放")
        print("📹 视频: \(videoURL)")
        print("📄 VTT: \(vttURL.path)")
        print("🖼️ Sprite: \(spriteURL.path)")

        // 关闭之前的播放器
        playerContainer.release()

        // 设置播放器准备好后的回调 - 在这里设置缩略图
        playerContainer.onPlayerReady = { [weak self] in
            guard let self = self else { return }
            print("📺 [播放器] 准备好，开始设置缩略图预览")
            // 🔑 关键：播放器准备好后才设置缩略图预览管理器
            self.setupThumbnailPreviewWithSprites(videoURL: URL(string: videoURL)!, vttURL: vttURL, spriteURL: spriteURL)
        }

        // 设置播放器
        playerContainer.setTitle("🎬 Big Buck Bunny (VTT+Sprite 测试)")
        playerContainer.setVideoConfig(url: videoURL, useProxy: false)

        // 开始播放
        playerContainer.play()

        // 註釋：不再顯示 VTT+Sprite 測試提示
        // DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
        //     let infoAlert = UIAlertController(
        //         title: "🎬 VTT + Sprite 测试",
        //         message: """
        //         ✅ 已加载 Big Buck Bunny
        //         ✅ 已加载本地 VTT 和 Sprite
        //
        //         📝 拖动进度条查看预览效果
        //
        //         VTT 覆盖范围：0:00 - 10:34
        //         缩略图间隔：约 25 秒
        //         """,
        //         preferredStyle: .alert
        //     )
        //     infoAlert.addAction(UIAlertAction(title: "开始测试", style: .default))
        //     self?.present(infoAlert, animated: true)
        // }
    }

    /// 设置缩略图预览管理器（VTT + Sprite 模式）
    private func setupThumbnailPreviewWithSprites(videoURL: URL, vttURL: URL, spriteURL: URL) {
        // 手动加载和解析 VTT + Sprite
        loadLocalVTTMetadata(vttURL: vttURL, spriteURL: spriteURL)

        print("✅ [缩略图] VTT + Sprite 模式已配置")
    }

    /// 加载本地 VTT 元数据
    private func loadLocalVTTMetadata(vttURL: URL, spriteURL: URL) {
        do {
            // 读取 VTT 文件内容
            let vttData = try Data(contentsOf: vttURL)

            // 解析 VTT（使用 sprite URL 作为 baseURL）
            let parser = ThumbnailSpriteParser()
            let success = parser.parse(data: vttData, baseURL: spriteURL.deletingLastPathComponent())

            if success {
                print("✅ [VTT] 解析成功，共 \(parser.metadataItems.count) 个缩略图")

                // 预加载 sprite 图片
                if let spriteImage = UIImage(contentsOfFile: spriteURL.path) {
                    parser.preloadSpriteImage(spriteImage, for: spriteURL)
                    print("✅ [Sprite] 图片已预加载，尺寸: \(spriteImage.size)")
                } else {
                    print("⚠️ [Sprite] 无法加载图片")
                }

                // 设置解析器到播放器容器
                playerContainer.setThumbnailParser(parser)
                print("✅ [管理器] 解析器已设置完成")
            } else {
                print("❌ [VTT] 解析失败")
            }
        } catch {
            print("❌ [VTT] 读取文件失败: \(error)")
        }
    }

    private func loadLongTestSubtitle() {
        print("📝 [字幕] 开始创建字幕文件...")

        // 创建覆盖整个视频的测试字幕 (约9分钟)
        // 使用更显眼的字幕内容
        let srtContent = """
1
00:00:00,000 --> 00:00:30,000
🎬 DXPlayerSDK 播放器演示

2
00:00:30,000 --> 00:01:00,000
📝 字幕功能正在运行

3
00:01:00,000 --> 00:01:30,000
⚡️ 支持播放速度调整 0.5x-2.0x

4
00:01:30,000 --> 00:02:00,000
📐 支持画面比例切换

5
00:02:00,000 --> 00:02:30,000
🎨 支持字幕样式自定义

6
00:02:30,000 --> 00:03:00,000
⏰ 支持字幕延迟调整

7
00:03:00,000 --> 00:03:30,000
💾 所有设置自动保存

8
00:03:30,000 --> 00:04:00,000
🔄 支持代理播放模式

9
00:04:00,000 --> 00:04:30,000
🎯 集成 FSPlayer 核心

10
00:04:30,000 --> 00:05:00,000
🎮 完整的播放控制功能

11
00:05:00,000 --> 00:05:30,000
🔐 支持加密视频播放

12
00:05:30,000 --> 00:06:00,000
✨ 字幕持续显示

13
00:06:00,000 --> 00:06:30,000
🔀 可切换多个字幕文件

14
00:06:30,000 --> 00:07:00,000
⚙️ 播放器性能优异

15
00:07:00,000 --> 00:07:30,000
🎉 感谢使用 DXPlayerSDK

16
00:07:30,000 --> 00:08:00,000
👋 播放即将结束

17
00:08:00,000 --> 00:08:30,000
🏁 最后 30 秒

18
00:08:30,000 --> 00:09:34,000
✅ 播放完成
"""

        // 保存到临时文件
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("long_test_subtitle_\(Int(Date().timeIntervalSince1970)).srt")

        print("📝 [字幕] 保存路径: \(tempURL.path)")

        do {
            try srtContent.write(to: tempURL, atomically: true, encoding: .utf8)
            print("📝 [字幕] 文件创建成功，开始加载...")

            let success = playerContainer.loadSubtitle(url: tempURL, autoActivate: true)
            if success {
                print("✅ [字幕] 加载并激活成功！字幕应该显示在视频底部")

                // 註釋：不再顯示字幕加載提示
                // let alert = UIAlertController(
                //     title: "字幕已加载",
                //     message: "中文字幕已自动加载\n请观察视频底部的字幕显示",
                //     preferredStyle: .alert
                // )
                // alert.addAction(UIAlertAction(title: "知道了", style: .default))
                //
                // DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                //     self?.present(alert, animated: true)
                // }
            } else {
                print("❌ [字幕] 加载失败！")
            }
        } catch {
            print("❌ [字幕] 创建文件失败: \(error)")
        }
    }

    // MARK: - 字幕加载方法

    /// 从远程 URL 下载字幕并加载
    /// - Parameter urlString: 字幕文件的 URL (支持 SRT, VTT 等格式)
    private func loadSubtitleFromURL(_ urlString: String) {
        print("📝 [字幕] 开始从 URL 下载字幕: \(urlString)")

        guard let url = URL(string: urlString) else {
            print("❌ [字幕] URL 格式错误: \(urlString)")
            return
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ [字幕] 下载失败: \(error.localizedDescription)")
                return
            }

            guard let data = data,
                  let subtitleContent = String(data: data, encoding: .utf8) else {
                print("❌ [字幕] 数据解析失败")
                return
            }

            print("✅ [字幕] 下载成功，大小: \(data.count) 字节")

            // 保存到临时文件
            let fileExtension = (urlString as NSString).pathExtension.isEmpty ? "srt" : (urlString as NSString).pathExtension
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("downloaded_subtitle_\(Int(Date().timeIntervalSince1970)).\(fileExtension)")

            do {
                try subtitleContent.write(to: tempURL, atomically: true, encoding: .utf8)
                print("📝 [字幕] 保存到临时文件: \(tempURL.path)")

                // 在主线程加载字幕
                DispatchQueue.main.async {
                    let success = self.playerContainer.loadSubtitle(url: tempURL, autoActivate: true)
                    if success {
                        print("✅ [字幕] 字幕加载成功")

                        // 註釋：不再顯示字幕加載提示
                        // let alert = UIAlertController(
                        //     title: "字幕已加载",
                        //     message: "已从远程服务器下载并加载字幕",
                        //     preferredStyle: .alert
                        // )
                        // alert.addAction(UIAlertAction(title: "知道了", style: .default))
                        // self.present(alert, animated: true)
                    } else {
                        print("❌ [字幕] 字幕加载失败")
                    }
                }
            } catch {
                print("❌ [字幕] 保存文件失败: \(error)")
            }
        }

        task.resume()
    }

    /// Mock 字幕数据（用于测试，未来替换为 API 调用）
    private func loadSintelSubtitleMock() {
        print("📝 [字幕] 使用 Mock 字幕数据...")

        // 测试字幕（先用纯英文测试）
        let srtContent = """
1
00:00:00,000 --> 00:00:10,000
SUBTITLE TEST - DXPlayerSDK

2
00:00:10,000 --> 00:00:20,000
This is a subtitle test

3
00:00:20,000 --> 00:00:30,000
You should see this text

4
00:00:30,000 --> 00:01:00,000
Testing subtitle display

5
00:01:00,000 --> 00:01:47,000
Dialogue will start soon

6
00:01:47,250 --> 00:01:50,500
This blade has a dark past

7
00:01:51,800 --> 00:01:55,800
它沾满了太多无辜者的鲜血

8
00:01:58,000 --> 00:02:01,450
你毫无准备就孤身前来，真是蠢到家了

9
00:02:01,750 --> 00:02:04,800
你还活着已经算是很走运了

10
00:02:05,250 --> 00:02:06,300
谢谢

11
00:02:07,500 --> 00:02:09,000
那么......

12
00:02:09,400 --> 00:02:13,800
是什么指引你来到了这片守护者之地？

13
00:02:15,000 --> 00:02:17,500
为了找人

14
00:02:18,000 --> 00:02:22,200
那人一定很重要吧？你的真情知己？

15
00:02:23,400 --> 00:02:25,000
她是一条龙

16
00:02:28,850 --> 00:02:31,750
孤身一人前往寻找可是很危险的

17
00:02:32,950 --> 00:02:35,870
这种孤独伴随我多久早已记不清了

18
00:03:27,250 --> 00:03:30,500
就快弄好了，嘘......

19
00:03:30,750 --> 00:03:33,500
嗨，坐那别动

20
00:03:48,250 --> 00:03:52,250
晚安啦，小麟

21
00:04:10,350 --> 00:04:13,850
追上它，小麟！加油哦！

22
00:04:25,250 --> 00:04:28,250
小麟？

23
00:05:04,000 --> 00:05:07,500
不错哦！加油！

24
00:05:38,750 --> 00:05:42,000
小麟！

25
00:07:25,850 --> 00:07:27,500
我失败了

26
00:07:32,800 --> 00:07:36,500
你只是败在盲目得去寻觅

27
00:07:37,800 --> 00:07:40,500
这里其实就是龙的国度了，辛泰奥

28
00:07:40,850 --> 00:07:44,000
你只是没有发觉离她有多近了

29
00:09:17,600 --> 00:09:19,500
小麟！

30
00:10:21,600 --> 00:10:24,000
小麟？

31
00:10:26,200 --> 00:10:29,800
小麟......
"""

        // 保存到临时文件 (使用 SRT 格式)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sintel_subtitle_\(Int(Date().timeIntervalSince1970)).srt")

        print("📝 [字幕] 保存路径: \(tempURL.path)")

        do {
            // 直接使用 UTF-8 编码保存（不添加 BOM）
            try srtContent.write(to: tempURL, atomically: true, encoding: .utf8)
            print("📝 [字幕] 文件创建成功，文件大小: \(srtContent.count) 字符")

            // 验证文件是否成功创建
            if FileManager.default.fileExists(atPath: tempURL.path) {
                print("✅ [字幕] 文件已创建: \(tempURL.path)")
            } else {
                print("❌ [字幕] 文件创建失败！")
                return
            }

            // 先配置字体样式（在加载字幕之前）- 使用最简单的配置
            // 注意：FSPlayer 使用 ASS 格式的 RGBA，其中 alpha=0 表示不透明，alpha=FF 表示透明
            print("🎨 [字幕] 预先配置字体样式...")
            playerContainer.configureSubtitleStyle(
                scale: 2.0,                      // 放大到 2 倍，确保能看见
                bottomMargin: 0.15,              // 底部边距更大
                fontName: "Helvetica",           // 使用最基本的字体
                textColor: 0xFFFFFF00,           // 白色，alpha=0 不透明
                outlineWidth: 4.0,               // 粗边框
                outlineColor: 0x00000000         // 黑色边框，alpha=0 不透明
            )
            print("🎨 [字幕] 样式配置完成 - 字体:Helvetica 大小:2.0x 颜色:FFFFFF00")

            // 延迟一点再加载字幕，确保样式配置生效
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }

                let success = self.playerContainer.loadSubtitle(url: tempURL, autoActivate: true)
                print("📊 [字幕] loadSubtitle 返回: \(success)")

                if success {
                    print("✅ [字幕] Sintel 字幕加载并激活成功！")

                    // 註釋：不再顯示字幕加載提示
                    // let alert = UIAlertController(
                    //     title: "字幕已加载",
                    //     message: "Sintel 中文字幕已自动加载\n字幕将在视频对话时显示",
                    //     preferredStyle: .alert
                    // )
                    // alert.addAction(UIAlertAction(title: "知道了", style: .default))
                    //
                    // DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    //     self?.present(alert, animated: true)
                    // }
                } else {
                    print("❌ [字幕] 加载失败！")
                }
            }
        } catch {
            print("❌ [字幕] 创建文件失败: \(error)")
        }
    }

    deinit {
        playerContainer?.release()
        ProxyServer.shared.stopAll()
    }

    // MARK: - 解密测试

    /// 测试 JM 格式解密逻辑
    private func testDecryption() {
        let alert = UIAlertController(title: "解密测试", message: "选择测试类型", preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "AA - Base64 测试", style: .default) { [weak self] _ in
            self?.testBase64Decryption()
        })

        alert.addAction(UIAlertAction(title: "AB - XOR 测试", style: .default) { [weak self] _ in
            self?.testXorDecryption()
        })

        alert.addAction(UIAlertAction(title: "AD - AES-CBC 测试", style: .default) { [weak self] _ in
            self?.testAesCbcDecryption()
        })

        alert.addAction(UIAlertAction(title: "运行所有测试", style: .default) { [weak self] _ in
            self?.runAllDecryptionTests()
        })

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))

        present(alert, animated: true)
    }

    /// 测试 AA (Base64) 解密
    /// 格式: [Base64内容] + [AA00 00] + [06]
    /// 说明: 类型AA + key长度00(0) + key空 + iv长度00(0) + iv空 + 头部长度06
    private func testBase64Decryption() {
        print("\n🔐 ====== 测试 AA (Base64) 解密 ======")

        // 原始内容: "Hello, DXPlayerSDK!"
        // Base64编码: "SGVsbG8sIERYUGxheWVyU0RLIQ=="
        // 加密约定: "AA" + "00" + "" + "00" + "" = "AA0000" (长度6)
        // 最终格式: Base64内容 + 加密约定 + 长度
        let testData = "SGVsbG8sIERYUGxheWVyU0RLIQ==AA000006"

        guard let data = testData.data(using: .utf8) else {
            print("❌ 无法创建测试数据")
            return
        }

        do {
            let result = try Decryptor.shared.decryptJmFormat(data)
            let decrypted = result.utf8String ?? "(无法转换为字符串)"
            print("✅ 解密成功!")
            print("   原始: Hello, DXPlayerSDK!")
            print("   解密: \(decrypted)")
            print("   匹配: \(decrypted == "Hello, DXPlayerSDK!" ? "✓" : "✗")")

            showDecryptionResult(title: "Base64 解密", expected: "Hello, DXPlayerSDK!", actual: decrypted)
        } catch {
            print("❌ 解密失败: \(error)")
            showDecryptionResult(title: "Base64 解密", expected: "Hello, DXPlayerSDK!", actual: "错误: \(error)")
        }
    }

    /// 测试 AB (XOR) 解密
    /// 格式: [XOR加密内容] + [AB{keyLen}{key}{ivLen}{iv}] + [头部长度]
    private func testXorDecryption() {
        print("\n🔐 ====== 测试 AB (XOR) 解密 ======")

        // 原始内容: "Test XOR"
        // Key: "KEY" (长度3)
        // XOR 加密: 每个字节与 key 循环异或
        let original = "Test XOR"
        let key = "KEY"

        // 手动 XOR 加密
        var encrypted = Data()
        let keyBytes = Array(key.utf8)
        for (i, byte) in original.utf8.enumerated() {
            encrypted.append(byte ^ keyBytes[i % keyBytes.count])
        }

        // 构建加密约定: "AB" + "03" + "KEY" + "00" + ""
        let header = "AB03KEY00"
        let headerLen = String(format: "%02d", header.count) // "09"

        // 最终数据: 加密内容 + 加密约定 + 长度
        var testData = encrypted
        testData.append(contentsOf: header.utf8)
        testData.append(contentsOf: headerLen.utf8)

        do {
            let result = try Decryptor.shared.decryptJmFormat(testData)
            let decrypted = result.utf8String ?? "(无法转换为字符串)"
            print("✅ 解密成功!")
            print("   原始: \(original)")
            print("   解密: \(decrypted)")
            print("   匹配: \(decrypted == original ? "✓" : "✗")")

            showDecryptionResult(title: "XOR 解密", expected: original, actual: decrypted)
        } catch {
            print("❌ 解密失败: \(error)")
            showDecryptionResult(title: "XOR 解密", expected: original, actual: "错误: \(error)")
        }
    }

    /// 测试 AD (AES-CBC) 解密
    private func testAesCbcDecryption() {
        print("\n🔐 ====== 测试 AD (AES-CBC) 解密 ======")

        // AES-128 需要 16 字节的 key 和 iv
        let key = "1234567890123456" // 16 bytes
        let iv = "abcdefghijklmnop"  // 16 bytes
        let original = "AES-CBC Test!!!" // 需要是 16 字节的倍数或使用 padding

        // 使用 Decryptor 的加密方法来创建测试数据
        // 由于我们只实现了解密，这里手动构造一个简单的测试
        // 实际测试需要后端提供加密数据

        print("⚠️ AES-CBC 测试需要后端提供加密数据")
        print("   Key: \(key)")
        print("   IV: \(iv)")
        print("   预期格式: [AES加密内容] + AD16\(key)16\(iv) + 头部长度")

        // 构建头部用于展示格式
        let header = "AD16\(key)16\(iv)"
        print("   头部示例: \(header) (长度:\(header.count))")

        showDecryptionResult(title: "AES-CBC 解密", expected: "需要后端数据", actual: "格式已准备就绪")
    }

    /// 运行所有解密测试
    private func runAllDecryptionTests() {
        print("\n🔐 ========== 运行所有解密测试 ==========\n")

        var results: [(String, Bool)] = []

        // 测试 1: Base64
        print("--- 测试 1: Base64 ---")
        let base64Test = "SGVsbG8sIERYUGxheWVyU0RLIQ==AA000006"
        if let data = base64Test.data(using: .utf8) {
            do {
                let result = try Decryptor.shared.decryptJmFormat(data)
                let success = result.utf8String == "Hello, DXPlayerSDK!"
                results.append(("Base64", success))
                print(success ? "✅ Base64 测试通过" : "❌ Base64 测试失败")
            } catch {
                results.append(("Base64", false))
                print("❌ Base64 测试异常: \(error)")
            }
        }

        // 测试 2: XOR
        print("\n--- 测试 2: XOR ---")
        let original = "Test XOR"
        let key = "KEY"
        var encrypted = Data()
        let keyBytes = Array(key.utf8)
        for (i, byte) in original.utf8.enumerated() {
            encrypted.append(byte ^ keyBytes[i % keyBytes.count])
        }
        let header = "AB03KEY00"
        let headerLen = String(format: "%02d", header.count)
        var xorTestData = encrypted
        xorTestData.append(contentsOf: header.utf8)
        xorTestData.append(contentsOf: headerLen.utf8)

        do {
            let result = try Decryptor.shared.decryptJmFormat(xorTestData)
            let success = result.utf8String == original
            results.append(("XOR", success))
            print(success ? "✅ XOR 测试通过" : "❌ XOR 测试失败")
        } catch {
            results.append(("XOR", false))
            print("❌ XOR 测试异常: \(error)")
        }

        // 汇总结果
        print("\n========== 测试结果汇总 ==========")
        let passed = results.filter { $0.1 }.count
        let total = results.count
        print("通过: \(passed)/\(total)")
        for (name, success) in results {
            print("  \(success ? "✅" : "❌") \(name)")
        }

        // 显示结果
        let message = results.map { "\($0.1 ? "✅" : "❌") \($0.0)" }.joined(separator: "\n")
        let resultAlert = UIAlertController(
            title: "解密测试结果",
            message: "通过: \(passed)/\(total)\n\n\(message)",
            preferredStyle: .alert
        )
        resultAlert.addAction(UIAlertAction(title: "确定", style: .default))
        present(resultAlert, animated: true)
    }

    /// 显示解密结果弹窗
    private func showDecryptionResult(title: String, expected: String, actual: String) {
        let success = expected == actual
        let message = """
        预期: \(expected)
        实际: \(actual)
        结果: \(success ? "✅ 匹配" : "❌ 不匹配")
        """

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}
