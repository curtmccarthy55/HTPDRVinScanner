# HTPDRVinScanner

A custom VIN scanner that works on barcodes and QR codes.

To use:
    1. Import the module into any files that need access to the scanner.
    2. One of your files must act as a delegate to the scanner view controller and adopt the VinScanControllerDelegate protocol.
    3. Instantiate an instance of the scanner view controller by calling CJMVinScannerViewController.vendViewController().
    4. Specify the delegate for the instance and present the view controller.
