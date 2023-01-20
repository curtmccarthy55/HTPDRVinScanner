//
//  CJMVinScanManager.swift
//  CJMVinScanner
//
//  Created by Curtis McCarthy on 5/28/22.
//

import Foundation
import AVFoundation
import Vision
import CoreImage

// MARK: - VinScanManagerDelegate

/// Delegate methods to receive results of a VIN scan session, either success, failure, or denial of permission.
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

// MARK: - CJMVinScanManager

/// A type responsible for overseeing the VIN scan session.  Manages permission and presentation of the camera/AVCaptureSession, handling VIN code detection and parsing, and returning results back to a VinScanManagerDelegate.
class CJMVinScanManager: NSObject { // NSObject required for AVCaptureVideoDataOutputSampleBufferDelegate.
    /// Delegate to receive results of VIN scan session.
    weak var delegate: VinScanManagerDelegate?
    
    
    // MARK: - AVCaptureSession Properties
    
    /// AVCaptureSession instance.
    private var captureSession = AVCaptureSession()
    
    // MARK: - VideoDeviceInput Properties
    
    /// The current video device input for the capture session.
    private(set) var videoDeviceInput: AVCaptureDeviceInput?
    
    /// The current video device input's maximum zoom factor (1.0 indicates that the format isn't capable of zooming).
    var videoMaxZoomFactor: Float {
        if let device = videoDeviceInput?.device {
            // Per Apple AVCamBarcode project recommendations, a cap of 8.0 is applied.
            return Float(min((device.activeFormat.videoMaxZoomFactor), CGFloat(8.0)))
        }

        return 1.0
    }
    
    /// The current zoom factor of the video device input.  Allowed values range from 1.0 (full field of view) to the value of the active format’s videoMaxZoomFactor property.
    var videoZoomFactor: Float {
        if let device = videoDeviceInput?.device {
            return Float(device.videoZoomFactor)
        }
        
        return 1.0
    }
    
    // MARK: - Vision Properties
    /// A VNRequest to detect barcodes.
    private lazy var detectBarcodeRequest = VNDetectBarcodesRequest(completionHandler: { [unowned self] (request, error) in
        if let error = error {
            delegate?.vinScanFailed(with: error)
            return
        }
        processClassification(request)
    })
    
    /// Boolean indicating if further scan processing should be stopped.
    private var blockAdditionalScans = false
    
    /* Image Altering Properties */
    /// The number of images that have been sent to VNDetectBarcodesRequest (every other image will have it's colors inverted).
    private var imageCount = 0
    
    /// Image converter to convert between image data types and apply filters.
    private lazy var imageConverter = CJMImageConverter()
    
    // MARK: - Set Up & Tear Down
    
    init(delegate: VinScanManagerDelegate) {
        self.delegate = delegate
    }
    
    deinit {
        captureSession.stopRunning()
    }
    
    // MARK: - Camera Handling
    
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
    
    /// Sets up the AVCaptureSession, AVCaptureDeviceInput and AVCaptureOutput,
    // func connectVisionCamera(_ previewView: CJMVinScannerView) {
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
        
        // Add the wide angle camera's input (data feed) as the session input.
        self.videoDeviceInput = videoDeviceInput
        captureSession.addInput(videoDeviceInput)
        
        // *** Create and add output ***
        let captureOutput = AVCaptureVideoDataOutput()
        captureOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        captureOutput.setSampleBufferDelegate(self,
                                              queue: DispatchQueue.global(qos: DispatchQoS.QoSClass.default))
        captureSession.addOutput(captureOutput)
        
        // Set the AVCaptureSession on our camera view.
//        let vinScanLayer = vinScannerView.layer as! AVCaptureVideoPreviewLayer
//        vinScanLayer.session = captureSession
        view.layer.session = captureSession // *** connection required here.
        
        // Start the capture session.  Shouldn't be called on main.
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let weakSelf = self else { return }
            weakSelf.captureSession.startRunning()
        }
    }
    
    /// Attempts to update the video zoom factor to the given magnification.
    func zoomCamera(magnification: Float) {
        do {
            try videoDeviceInput?.device.lockForConfiguration()
            videoDeviceInput?.device.videoZoomFactor = CGFloat(magnification)
            videoDeviceInput?.device.unlockForConfiguration()
        }
        catch {
            #if DEBUG
            print("Could not lock for configuration: \(error)")
            #endif
        }
    }
    
    //MARK: - AV and Vision Handling
    
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
        // Get a CIIimage from the sample buffer.
        guard let ciImage = imageConverter.convertSampleBuffer(sampleBuffer) else {
            return
        }

        // Every other image, invert the colors before attempting barcode detection.
        let finalImage: CIImage
        if imageCount % 2 == 0 {
            #if DEBUG
            print("*** Using normal image ***")
            #endif
            finalImage = ciImage
        }
        else {
            if let invertedImage = imageConverter.invertImage(ciImage) {
                #if DEBUG
                print("*** Using inverted image ***")
                #endif
                finalImage = invertedImage
            }
            else {
                #if DEBUG
                print("*** Falling back to normal image after invert image fail ***")
                #endif
                finalImage = ciImage
            }
        }
        imageCount += 1

        // Make a new VNImageRequestHandler using that image.
        // TODO make sure .right is the orientation we want here.
        let imageRequestHandler = VNImageRequestHandler(ciImage: finalImage,
                                                        orientation: .right,
                                                        options: [:])

        // Perform the detectBarcodeRequest using the handler.
        do {
            try imageRequestHandler.perform([detectBarcodeRequest])
            print("*** Performing new detect barcodes request on CIImage. ***")
        }
        catch {
            print(error)
        }
    }
    
//    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//        // Get an image out of sample buffer, like a page out of a flip book.
//        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
//            return
//        }
//
//        // Make a new VNImageRequestHandler using that image.
//        // TODO make sure .right is the orientation we want here.
//        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
//                                                        orientation: .right,
//                                                        options: [:])
////        let newImageRequestHandler = VNImageRequestHandler(...)
//
//        // Perform the detectBarcodeRequest using the handler.
//        do {
//            try imageRequestHandler.perform([detectBarcodeRequest])
//            print("Performing detect barcodes request on image...")
//        } catch {
//            print(error)
//        }
//    }
}

/// A type to handle converting image types and applying filters.
fileprivate final class CJMImageConverter {
    /// A CIFilter to invert colors in the image.
    private lazy var colorInvert: CIFilter? = CIFilter(name: "CIColorInvert")
    
    /// A method to invert the colors of a given image.
    /// - Parameter sampleImage: Some sample image (image type pending... at the moment, either a CMSampleBuffer or CVPixelBuffer, but this will depend on optimization)
    /// - Returns: The inverted image (again, image type pending... the image that gets returned will need to be passed to a VNImageRequestHandler, and that can technically consume image data in a number of formats - CGImage, CIImage, CVPixelBuffer, CMSampleBuffer, Data, and URL (i.e. presumably a path to some image))
    func invertImage(_ sampleImage: CIImage) -> CIImage? {
//        guard let filter = CIFilter(name: "CIColorInvert") else {
//            return nil
//        }
//        filter.setValue(sampleImage,
//                        forKey: kCIInputImageKey)
//        let invertedImage = filter.outputImage
        
        guard colorInvert != nil else {
            return nil
        }
        colorInvert?.setValue(sampleImage,
                         forKey: kCIInputImageKey)
        let invertedImage = colorInvert?.outputImage
        
        return invertedImage
    }
    
    /// Converts a CMSampleBuffer to a CIImage.
    /// - Parameter sampleBuffer: A CMSampleBuffer.
    /// - Returns: A CIImage, if one was able to be generated from the given CMSampleBuffer.
    func convertSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> CIImage? {
        guard let cvImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        let ciImage = CIImage(cvPixelBuffer: cvImageBuffer)
        return ciImage
    }
}
