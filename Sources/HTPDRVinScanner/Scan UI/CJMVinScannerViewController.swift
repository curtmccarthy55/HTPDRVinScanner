//
//  CJMVinScannerViewController.swift
//  CJMVinScanner
//
//  Created by Curtis McCarthy on 3/10/22.
//

import UIKit
import AVFoundation
import Vision

// MARK: - VinScanControllerDelegate

/// Protocol to handle simple communication from a single-task view controller.
public protocol VinScanControllerDelegate: AnyObject {
    /// Cancel tapped on view controller.
    func vinScanControllerDidCancel()
    
    /// Submit the results of the task.
    func vinScanController(_ viewController: UIViewController, finishedWithResult result: Result<String?, Error>)
}

// MARK: - CJMVinScannerViewController

/// ViewController for the VIN scanner UI.
open class CJMVinScannerViewController: UIViewController {
    
    // MARK: Properties
    public weak var delegate: VinScanControllerDelegate?
    
    private lazy var vinScanManager: CJMVinScanManager = {
        let manager = CJMVinScanManager(delegate: self)
        return manager
    }()
    
    // MARK: Outlet Properties
    
    /// The viewport for the VIN scanner.
    @IBOutlet private weak var vinScannerView: CJMVinScannerView!
    
    /// Visual supplement.  Provides black background prior to the camera becoming active.  Prevents underlying UI from showing through during VIN scanner presentation.
    @IBOutlet private weak var shutterView: UIView?
    
    /// UISwitch controlling the torch.
    @IBOutlet private weak var lightSwitch: UISwitch!
    
    /// Zoom control slider.
    @IBOutlet weak var zoomSlider: UISlider!
    
    /// Horizontal stack view for the light switch and associated labels.
    @IBOutlet private weak var lightSwitchStack: UIStackView!
    
    /// Cancel button, calls on delegate to dismiss the scene.
    @IBOutlet private weak var cancelButton: UIButton!
    
    /// A decorative thin, red, transparent "scan" line.  Centered horizontally and spans the width of the viewport.
    @IBOutlet private weak var scanLine: UIView!
    
    //MARK: - Scene Set Up
    
    /// Instantiates and returns a CJMVinScannerViewController instance.
    public static func instance(withDelegate delegate: VinScanControllerDelegate) -> CJMVinScannerViewController {
        let vc = CJMVinScannerViewController(nibName: "CJMVinScannerViewController",
                                             bundle: Bundle.module)
        vc.delegate = delegate
        vc.modalPresentationStyle = .fullScreen
        
        return vc
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        cancelButton.setTitle("Cancel", for: .normal)
        scanLine.isHidden = true
        setupLightSwitch()
        vinScanManager.checkPermissions()
        setupViewPort()
        setupZoomSlider()
    }
    
    public override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      
      correctVideoOrientation()
    }
    
    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        shutterView?.removeFromSuperview()
    }
    
    /// Sets min, max, and initial zoom values on the zoom slider.
    private func setupZoomSlider() {
        zoomSlider.maximumValue = vinScanManager.videoMaxZoomFactor
        zoomSlider.minimumValue = 1.0
        zoomSlider.value = vinScanManager.videoZoomFactor
        #if DEBUG
        print("zoomSlider.minimumValue == \(zoomSlider.minimumValue)")
        print("zoomSlider.maximumValue == \(zoomSlider.maximumValue)")
        print("zoomSlider.value == \(zoomSlider.value)")
        #endif
    }
    
    @IBAction private func zoomCamera(with zoomSlider: UISlider) {
        #if DEBUG
        print("Attempting zoom to \(zoomSlider.value)")
        #endif
        vinScanManager.zoomCamera(magnification: zoomSlider.value)
    }
    
    /// Checks for torch access and sets up the light switch stack state and connections accordingly.
    private func setupLightSwitch() {
        // Confirm the presence of a device torch.
        guard let device = AVCaptureDevice.default(for: .video),
        device.hasTorch else {
            lightSwitchStack.isHidden = true
            return
        }
        
        // *** Set the light switch's colors ***
        // For the on position.
        lightSwitch.onTintColor = .white
        // For the off position.
        lightSwitch.backgroundColor = UIColor(white: 0.0, alpha: 1.0)
        lightSwitch.layer.cornerRadius = 16.0
        // Thumb color.
        lightSwitch.thumbTintColor = .lightGray
        
        // Set the light switch state and connection.
        lightSwitchStack.isHidden = false
        lightSwitch.setOn(false, animated: false)
        lightSwitch.addTarget(self,
                              action: #selector(lightSwitchFlipped),
                              for: .valueChanged)
    }
    
    /// Correct the video orientation per the current device orientation.
    private func correctVideoOrientation() {
        // Handle video orienation.
        if let connection = vinScannerView.layer.connection {
            let currentDevice = UIDevice.current
            let orientation: UIDeviceOrientation = currentDevice.orientation
            let previewLayerConnection: AVCaptureConnection = connection
            
            if previewLayerConnection.isVideoOrientationSupported {
                switch orientation {
                case .portrait:
                    updatePreviewLayer(layer: previewLayerConnection,
                                       orientation: .portrait)
                case .landscapeRight:
                    updatePreviewLayer(layer: previewLayerConnection,
                                       orientation: .landscapeLeft)
                case .landscapeLeft:
                    updatePreviewLayer(layer: previewLayerConnection,
                                       orientation: .landscapeRight)
                case .portraitUpsideDown:
                    updatePreviewLayer(layer: previewLayerConnection,
                                       orientation: .portraitUpsideDown)
                default:
                    updatePreviewLayer(layer: previewLayerConnection,
                                       orientation: .portrait)
                }
            }
        }
    }
    
    /// Fixes orientation on viewport. // TODO get better understanding of this.
    private func updatePreviewLayer(layer: AVCaptureConnection, orientation: AVCaptureVideoOrientation) {
        layer.videoOrientation = orientation
        vinScannerView.layer.frame = view.bounds // TODO consider not doing this frame manipulation here.
    }
    
    /// Connects the camera preview layer to the AVCaptureSession.
    private func setupViewPort() {
        vinScanManager.connectViewPort(vinScannerView)
    }
    
    //MARK: - Button Actions
    
    @IBAction private func tappedCancel() {
        delegate?.vinScanControllerDidCancel()
    }
    
    /// Toggles the torch based on the current light switch position.
    @objc private func lightSwitchFlipped() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            return
        }
        
        // Check for permission to access the torch.
        do {
            try device.lockForConfiguration()
            // If lock successful, update the torch per the light switch.
            if lightSwitch.isOn {
                try device.setTorchModeOn(level: 1.0)
            } else {
                device.torchMode = .off
            }
        } catch {
            showAlert(withTitle: "Torch Failed",
                      message: "Torch toggle failed with error: \(error.localizedDescription).")
        }
        
        device.unlockForConfiguration()
    }
    
    // MARK: - Error Handling
    
    /// Convenience method to create and present an alert with the given title, message, and an "OK" dismissal action.
    /// - Parameters:
    ///    - title: The alert title.
    ///    - message the alert message.
    private func showAlert(withTitle title: String?, message: String?) {
        DispatchQueue.main.async {
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alertController, animated: true)
        }
    }
    
    /// Show alert for denied access to the camera.
    private func showPermissionsAlert() {
        // Prepare alert.
        let title = NSLocalizedString("Permission Denied", comment: "Localized text: Permission Denied")
        let message = NSLocalizedString("Please open Settings and grant permission for this app to use your camera.", comment: "Localized text: Camera permission message")
        let alert = UIAlertController(title: title,
                                      message: message,
                                      preferredStyle: .alert)
        
        // Add navigation to settings, if able.
        if let settingsURL = URL(string: UIApplication.openSettingsURLString),
           UIApplication.shared.canOpenURL(settingsURL) {
            let openSettingsCopy = NSLocalizedString("Open Settings",
                                                     comment: "Localized text: Open Settings")
            let settings = UIAlertAction(title: openSettingsCopy,
                                         style: .default) { _ in
                UIApplication.shared.open(settingsURL)
            }
            alert.addAction(settings)
        }
        
        // Add dismiss.
        let dismissCopy = NSLocalizedString("Dismiss", comment: "Localized text: Dismiss")
        let dismiss = UIAlertAction(title: dismissCopy, style: .default)
        alert.addAction(dismiss)
        
        DispatchQueue.main.async { [weak self] in
            guard let weakSelf = self else { return }
            weakSelf.present(alert, animated: true)
        }
    }
}

// MARK: - VinScanManagerDelegate

extension CJMVinScannerViewController: VinScanManagerDelegate {
    func vinScanPermissionDenied() {
        showPermissionsAlert()
    }
    
    func vinScanSucceeded(with code: String) {
        delegate?.vinScanController(self,
                                    finishedWithResult: .success(code))
    }
    
    func vinScanFailed(with error: Error) {
        showAlert(withTitle: "Scanner Error",
                  message: "VIN scan failed with an error: \(error.localizedDescription)")
    }
    
    func vinScanUnavailable() {
        showAlert(withTitle: "Cannot Find Camera",
                  message: "There seems to be a problem with the camera on your device.")
    }
}
