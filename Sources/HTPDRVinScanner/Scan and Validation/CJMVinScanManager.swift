//
//  CJMVinScanManager.swift
//  CJMVinScanner
//
//  Created by Curtis McCarthy on 5/28/22.
//

import Foundation
import AVFoundation
import Vision

protocol VinScanManagerDelegate: AnyObject {
    /// Some technology needed by the VIN scanner has been disabled (i.e. camera access).
    func vinScanPermissionDenied()
    /// VIN scan succeeded with the given code.
    func vinScanSucceeded(with code: String)
    /// VIN scan failed with the given error.
    func vinScanFailed(with error: Error)
    /// This device cannot scan VIN codes (e.g. no camera).
    func vinScanUnavailable()
}

class CJMVinScanManager: NSObject { // NSObject inheritance required for conformance to AVCaptureVideoDataOutputSampleBufferDelegate.
    weak var delegate: VinScanManagerDelegate?
    
    /// AVCaptureSession instance.
    private var captureSession = AVCaptureSession()
    
    /// A VNRequest to detect barcodes.
    private lazy var detectBarcodeRequest = VNDetectBarcodesRequest { [unowned self] request, error in
        if let error = error {
            delegate?.vinScanFailed(with: error)
            return
        }
//        guard error == nil else {
//            showAlert(withTitle: "Barcode Error",
//                           message: error!.localizedDescription)
//            return
//        }
        
        processClassification(request)
    }
    
    /// Boolean indicating if further scan processing should be stopped.
    private var blockAdditionalScans = false
    
    // MARK: - Set Up & Tear Down
    
    init(delegate: VinScanManagerDelegate) {
        self.delegate = delegate
    }
    
    deinit {
        captureSession.stopRunning()
    }
    
    func connectViewPort(_ view: CJMVinScannerView) {
        // *** Modify capture session ***
        captureSession.sessionPreset = .hd1280x720
        
        // *** Add input ***
        // Find the default wide angle camera, located on the rear of the iPhone.
        let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                  for: .video,
                                                  position: .back)
        
        // Make sure your app can use the camera as an input device for the capture session.
        guard let device = videoDevice,
              let videoDeviceInput = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(videoDeviceInput) else {
                  // If there's a problem with the camera, show an alert.
            delegate?.vinScanUnavailable()
                  return
              }
        
        // Otherwise, set the rear wide angle camera as the input device for the capture session.
        captureSession.addInput(videoDeviceInput)
        
        // *** Create and add output ***
        let captureOutput = AVCaptureVideoDataOutput()
        // Set sample rate.
        captureOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        captureOutput.setSampleBufferDelegate(self,
                                              queue: DispatchQueue.global(qos: DispatchQoS.QoSClass.default))
        captureSession.addOutput(captureOutput)
        
        // Set the AVCaptureSession on our camera view.
//        let vinScanLayer = vinScannerView.layer as! AVCaptureVideoPreviewLayer
//        vinScanLayer.session = captureSession
        view.layer.session = captureSession // *** connection required here.
        
        // Start the capture session.
        captureSession.startRunning()
    }
    
    //MARK: - AV and Vision Handling
    
    /// Check camera permission.
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            // When the status isn’t determined, meaning the user hasn’t made a permissions selection yet, you call AVCaptureDevice.requestAccess(for:completionHandler:). It presents the user with a dialog asking for permission to use the camera. If the user denies your request, you show a pop-up message asking for permission again, this time in the iPhone settings.
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let weakSelf = self else { return }
                if !granted {
                    weakSelf.delegate?.vinScanPermissionDenied()
                }
            }
        case .denied, .restricted:
            // If the user previously provided restricted access to the camera, or denied the app access to the camera, you show an alert asking for an update to settings to allow access.
            delegate?.vinScanPermissionDenied()
        default:
            // Otherwise, the user already granted permission for your app to use the camera, so you don’t have to do anything.
            return
        }
    }
    
    /// Handle a new VNRequest.
    private func processClassification(_ request: VNRequest) {
        // Get a list of potential barcodes from the request.
        guard let barcodes = request.results else {
            return
        }
        
        DispatchQueue.main.async { [self] in
            if blockAdditionalScans {
                return
            }
            
            if captureSession.isRunning {
                // Loop through the potential barcodes to analyze each one individually.
                for barcode in barcodes {
                    guard let potentialCode = barcode as? VNBarcodeObservation,
                          let confirmedCode = potentialCode.payloadStringValue else {
                        // Keep scanning until we get a result or the user cancels.
                        return
                    }
                    
                    // Perform validation check on confirmedCode.  VIN code may be nested with other data.
                    let codeComponents = confirmedCode.split(separator: ",")
                    for component in codeComponents {
                        guard let sanitizedCode = CJMVinValidator.sanitizePossibleVIN(code: String(component)) else {
                            continue
                        }
                        
                        if CJMVinValidator.isValidVIN(code: sanitizedCode) {
                            // Once we have a valid vin code, stop all further delegate callbacks.
                            blockAdditionalScans = true
                            
                            // If a potential code has been returned, make use of it.
                            print("successfully scanned vin: \(sanitizedCode)")
                            delegate?.vinScanSucceeded(with: sanitizedCode)
                            return
                        }
                    }
                    #if DEBUG
                    print("Scanned code is not a VIN.")
                    #endif
                }
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CJMVinScanManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Get an image out of sample buffer, like a page out of a flip book.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // Make a new VNImageRequestHandler using that image. TODO make sure .right is the orientation we want here.
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                        orientation: .right,
                                                        options: [:])
        
        // Perform the detectBarcodeRequest using the handler.
        do {
            try imageRequestHandler.perform([detectBarcodeRequest])
        } catch {
            print(error)
        }
    }
}
