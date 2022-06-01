//
//  CJMVinScannerView.swift
//  CJMVinScanner
//
//  Created by Curtis McCarthy on 3/10/22.
//

import Foundation
import UIKit
import AVFoundation

/// UIView subclass that replaces it's CALayer with AVCaptureVideoPreviewLayer.
class CJMVinScannerView: UIView {
    // MARK: - Overridden Properties
    
    override class var layerClass: AnyClass  {
        return AVCaptureVideoPreviewLayer.self
    }
    
    override var layer: AVCaptureVideoPreviewLayer {
        return super.layer as! AVCaptureVideoPreviewLayer
    }
    
    // MARK: - Init
    
    required override init(frame: CGRect) {
        super.init(frame: frame)
        setupVinScannerView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupVinScannerView()
    }
    
    // MARK: - Scene Set Up
    
    /// Adjust AVCaptureVideoPreviewLayer display.
    private func setupVinScannerView() {
        self.layer.videoGravity = .resizeAspectFill
    //    self.layer.connection?.videoOrientation = .portrait
    //    self.layer.frame = view.frame
    }
    
}
