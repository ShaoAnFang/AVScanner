//
//  AVScannerViewController.swift
//  AVScanner
//
//  Created by mrfour on 16/12/2016.
//  Copyright © 2016 mrfour. All rights reserved.
//

import UIKit
import AVFoundation

class AVScannerViewController: UIViewController {
    
//    open var barcodeHandler: ((_ barcodeObject: AVMetadataMachineReadableCodeObject, _ barcodeCorners: [Any]) -> Void)?
    open var barcodeHandler: ((_ barcodeString: String) -> Void)?
    
    // MARK: - Device configuration
    
    private let videoDeviceDiscoverySession = AVCaptureDeviceDiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDuoCamera], mediaType: AVMediaTypeVideo, position: .unspecified)
    
    // MARK: - Session management
    
    fileprivate enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    fileprivate let previewView = AVScannerPreviewView()
    fileprivate var setupResult: SessionSetupResult = .success
    open var isSessionRunning = false
    
    fileprivate let session = AVCaptureSession()
    fileprivate let sessionQueue = DispatchQueue(label: "session queue")
    
    var videoDeviceInput: AVCaptureDeviceInput!
    
    // MARK: - Meta data output
    
    let captureMetaDataOutput = AVCaptureMetadataOutput()
    
    // MARK: - Focus view
    
    let focusView = AVScannerFocusView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
    
    // MARK: - View controller life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        prepareView()
        
        previewView.session = session
        
        switch AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo) {
        case .authorized: break
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: { [unowned self] granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
        default:
            setupResult = .notAuthorized
        }
        
        sessionQueue.async { [unowned self] in
            self.configureSession()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startRunningSession()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        stopRunningSession()
        super.viewWillDisappear(animated)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        focusView.layer.anchorPoint = CGPoint.zero
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        if isSessionRunning {
            focusView.startAnimation()
        }
        
        let deviceOrientation = UIDevice.current.orientation
        
        guard let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection ,
              let newVideoOrientation = deviceOrientation.videoOrientation, deviceOrientation.isPortrait || deviceOrientation.isLandscape else { return }
        
        videoPreviewLayerConnection.videoOrientation = newVideoOrientation
    }
    
    override var shouldAutorotate: Bool {
        get {
            return isSessionRunning
        }
    }
    // MARK: - Prepare view
    
    private func prepareView() {
        preparePreviewView()
        prepareFocusView()
    }
    
    private func preparePreviewView() {
        view.addSubview(previewView)
        
        previewView.translatesAutoresizingMaskIntoConstraints = false
        let centerXConstraint = NSLayoutConstraint(item: view, attribute: .centerX, relatedBy: .equal, toItem: previewView, attribute: .centerX, multiplier: 1, constant: 0)
        let centerYConstraint = NSLayoutConstraint(item: view, attribute: .centerY, relatedBy: .equal, toItem: previewView, attribute: .centerY, multiplier: 1, constant: 0)
        let heightConstraint  = NSLayoutConstraint(item: view, attribute: .height, relatedBy: .equal, toItem: previewView, attribute: .height, multiplier: 1, constant: 0)
        let widthConstraint   = NSLayoutConstraint(item: view, attribute: .width, relatedBy: .equal, toItem: previewView, attribute: .width, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([centerXConstraint, centerYConstraint, heightConstraint, widthConstraint])
    }
    
    private func prepareFocusView() {
//        focusView.alpha = 0
        view.addSubview(focusView)
        view.bringSubview(toFront: focusView)
    }
    
    // MARK: - Configure 
    
    private func configureSession() {
        guard setupResult == .success else { return }
        
        session.beginConfiguration()
        
        do {
            var defaultVideoDevice: AVCaptureDevice?
            
            if let dualCameraDevice = AVCaptureDevice.defaultDevice(withDeviceType: .builtInDuoCamera, mediaType: AVMediaTypeVideo, position: .back) {
                defaultVideoDevice = dualCameraDevice
            } else if let backCameraDevice = AVCaptureDevice.defaultDevice(withDeviceType: .builtInWideAngleCamera, mediaType: AVMediaTypeVideo, position: .back) {
                defaultVideoDevice = backCameraDevice
            } else if let frontCameraDevice = AVCaptureDevice.defaultDevice(withDeviceType: .builtInWideAngleCamera, mediaType: AVMediaTypeVideo, position: .front) {
                defaultVideoDevice = frontCameraDevice
            }
            
            let videoDeviceInput = try AVCaptureDeviceInput(device: defaultVideoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                DispatchQueue.main.async {
                    let statusBarOrientation = UIApplication.shared.statusBarOrientation
                    var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                    if statusBarOrientation != .unknown {
                        if let videoOrientation = statusBarOrientation.videoOrientation {
                            initialVideoOrientation = videoOrientation
                        }
                    }
                    
                    self.previewView.videoPreviewLayer.connection.videoOrientation = initialVideoOrientation
                }
            } else {
                setupResult = .configurationFailed
                session.commitConfiguration()
            }
            
        } catch let error as NSError {
            print(error.localizedDescription)
            print("Could not add video device input to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.addOutput(captureMetaDataOutput)
        captureMetaDataOutput.setMetadataObjectsDelegate(self, queue: sessionQueue)
        captureMetaDataOutput.metadataObjectTypes = [AVMetadataObjectTypeQRCode]
        
        session.commitConfiguration()
    }
    
    // MARK: - Session control 
    
    open func startRunningSession() {
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                DispatchQueue.main.async { [unowned self] in
                    self.focusView.startAnimation()
                }
            case .notAuthorized:
                DispatchQueue.main.async { [unowned self] in
                    let message = NSLocalizedString("AVCam doesn't have permission to use the camera, please change privacy settings", comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"), style: .`default`, handler: { action in
                        UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            case .configurationFailed:
                DispatchQueue.main.async { [unowned self] in
                    let message = NSLocalizedString("Unable to capture media", comment: "Alert message when something goes wrong during capture session configuration")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    private func stopRunningSession() {
        sessionQueue.async { [unowned self] in
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
            }
        }
    }
    
    // MARK: - KVO and Notification
    
}

// MARK: - AV Capture

extension AVScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputMetadataObjects metadataObjects: [Any]!, from connection: AVCaptureConnection!) {
        guard let barcodeObject = metadataObjects.first as? AVMetadataObject, let transformedMetadataObject = previewView.videoPreviewLayer.transformedMetadataObject(for: barcodeObject) as? AVMetadataMachineReadableCodeObject else { return }
        print("captured output")
        sessionQueue.async { [unowned self] in
            self.session.stopRunning()
            self.isSessionRunning = self.session.isRunning
            
            DispatchQueue.main.async { [unowned self] in
                self.focusView.transform(to: transformedMetadataObject.corners) { [unowned self] in
                    self.barcodeHandler?(transformedMetadataObject.stringValue)
                }
            }
        }
    }
}

/*
extension AVScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputMetadataObjects metadataObjects: [Any]!, from connection: AVCaptureConnection!) {
        var barcodeObjects = [AVMetadataMachineReadableCodeObject]()
        var corners = [Any]()
        
        for metadataObject in metadataObjects as! [AVMetadataObject] {
            guard let transformedMetadataObject = previewView.videoPreviewLayer.transformedMetadataObject(for: metadataObject), transformedMetadataObject is AVMetadataMachineReadableCodeObject else { continue }
            let barcodeObject = transformedMetadataObject as! AVMetadataMachineReadableCodeObject
            barcodeObjects.append(barcodeObject)
            corners.append(barcodeObject.corners)
        }
        
        guard barcodeObjects.count > 0 else { return }
        barcodeHandler?(barcodeObjects, corners)
    }
}
*/

// MARK: - Device orientation

extension UIDeviceOrientation {
    var videoOrientation: AVCaptureVideoOrientation? {
        switch self {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default: return nil
        }
    }
}

// MARK: - Interface orientation

extension UIInterfaceOrientation {
    var videoOrientation: AVCaptureVideoOrientation? {
        switch self {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return nil
        }
    }
}

























