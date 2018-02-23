//
//  ViewController.swift
//  Save session in ARKit with CoreML
//
//  Based on the code of CoreML in ARkit by Hanley Weng
//  Created by Alessandro La Conca on 21/02/2018
//

import UIKit
import SceneKit
import ARKit

import Vision

class ViewController: UIViewController, ARSCNViewDelegate {

    // SCENE
    @IBOutlet var sceneView: ARSCNView!

    var latestPrediction : String = "…" // a variable containing the latest CoreML prediction
    var anchorFound : Bool = false // a variable indicating if the anchor node is currently on the screen
    var nodeCoord : [[Float]] = [[0, 0, 0]] // an array of rows x,y,z of posion of nodes, the first is the anchor
    let defaults = UserDefaults.standard
    
    let bubbleDepth : Float = 0.01 // the 'depth' of 3D text
    var nodeText : [String] = ["mouse"] // an array of names, the first is name of the anchor node

    
    //ADD node on click
    @IBAction func AddButton(_ sender: Any) {

        // HIT TEST : REAL WORLD
        // Get Screen Centre
        let screenCentre : CGPoint = CGPoint(x: self.sceneView.bounds.midX, y: self.sceneView.bounds.midY)
        
        let arHitTestResults : [ARHitTestResult] = sceneView.hitTest(screenCentre, types: [.featurePoint]) // Alternatively, we could use '.existingPlaneUsingExtent' for more grounded hit-test-points.
        
        if let closestResult = arHitTestResults.first {
            // Get Coordinates of HitTest
            let transform : matrix_float4x4 = closestResult.worldTransform
            let hitCoord : SCNVector3 = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            
            // If the anchor node is on the screen adds all the nodes to the scene
            if anchorFound
            {
                // Remove all nodes from the scene
                sceneView.scene.rootNode.enumerateChildNodes { (node, stop) -> Void in
                    node.removeFromParentNode()
                }
                
                // Place all the nodes saved in the memory from a precedent session
                // The node in 0 is the anchor node so it need to be shisted as last
                for row in (0..<nodeCoord.count).reversed() {
                    
                    let node0 : SCNNode = createNewBubbleParentNode(nodeText[row])//Create a new node
                    sceneView.scene.rootNode.addChildNode(node0)//Add it to the root node
                    
                    // Shift the array of positions by the difference between the new and the old anchor position
                    nodeCoord[row]=[hitCoord.x-nodeCoord[0][0]+nodeCoord[row][0],
                                      hitCoord.y-nodeCoord[0][1]+nodeCoord[row][1],
                                      hitCoord.z-nodeCoord[0][2]+nodeCoord[row][2]]
                    
                    // Move the node to the previously assigned position
                    node0.position = SCNVector3(nodeCoord[row][0],nodeCoord[row][1],nodeCoord[row][2])
                }
                
                // Save data of the new nodes position in respect to the new anchor position
                defaults.set(nodeCoord, forKey: "nodeCoord")
            }
            // If the anchor node is not on the screen add a new node with the text you type
            else
            {
                // 1. Create the alert controller.
                let alert = UIAlertController(title: "Text to display", message: "Enter the text you want to display", preferredStyle: .alert)
                
                // 2. Add the text field, the default value is the name of the node on the screen
                alert.addTextField { (textField) in
                    textField.text = self.latestPrediction
                }
                
                // 3. Grab the value from the text field, and display it when the user clicks OK.
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak alert] (_) in
                    let textFieldText = alert?.textFields![0].text ?? "" //Creates a string with the content of the text field
                    //Creates a node with the content of the text field
                    let node : SCNNode = self.createNewBubbleParentNode(""+textFieldText)
                    self.sceneView.scene.rootNode.addChildNode(node)
                    node.position = hitCoord
                    
                    //Save data of the node
                    self.nodeCoord.append([hitCoord.x,hitCoord.y,hitCoord.z])
                    self.nodeText.append(textFieldText)
                    
                    self.defaults.set(self.nodeText, forKey: "nodeText")
                    self.defaults.set(self.nodeCoord, forKey: "nodeCoord")
                    
                }))
                // Cancel
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action: UIAlertAction!) in
                    print("Cancel")
                }))
                // Present the alert.
                self.present(alert, animated: true, completion: nil)
                
            }
        }
    }
    
    @IBAction func ResetButton(_ sender: UIButton) {
        // Remove all nodes
        sceneView.scene.rootNode.enumerateChildNodes { (node, stop) -> Void in
            node.removeFromParentNode()
        }
        // Reinizialize varibles
        defaults.removeObject(forKey: "nodeCoord")
        defaults.removeObject(forKey: "nodeText")
        
        nodeCoord = [[0, 0, 0]]
        nodeText = [nodeText[0]]
        
        defaults.set(nodeText, forKey: "nodeText")
    }
    
    
    @IBAction func ChangeAnchor(_ sender: UIButton) {
        // 1. Create the alert controller.
        let alert = UIAlertController(title: "Change Anchor Name", message: "Enter the name of the object that will be the next anchor, all current objects are gonna be resetted", preferredStyle: .alert)
        
        // 2. Add the text field, the default value is the name of the object on the screen
        alert.addTextField { (textField) in
            textField.text = self.latestPrediction
        }
        
        // 3. Grab the value from the text field, and use it as the new anchor when the user clicks OK.
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak alert] (_) in
            
            // Remove all nodes
            self.sceneView.scene.rootNode.enumerateChildNodes { (node, stop) -> Void in
                node.removeFromParentNode()
            }
            
            // Reinizialize varibles
            self.defaults.removeObject(forKey: "nodeCoord")
            self.defaults.removeObject(forKey: "nodeText")
            
            self.nodeCoord = [[0, 0, 0]]
            self.nodeText = [alert?.textFields![0].text ?? self.nodeText[0]] // Assign the content of the the text field as the new anchor
            
        }))
        // Cancel
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action: UIAlertAction!) in

        }))
        // Present the alert.
        self.present(alert, animated: true, completion: nil)

    }
    
    // COREML
    var visionRequests = [VNRequest]()
    let dispatchQueueML = DispatchQueue(label: "com.hw.dispatchqueueml") // A Serial Queue
    @IBOutlet weak var debugTextView: UITextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        
        // Create a new scene
        let scene = SCNScene()
        
        // Set the scene to the view
        sceneView.scene = scene
        
        // Enable Default Lighting - makes the 3D text a bit poppier.
        sceneView.autoenablesDefaultLighting = true
        
        // Load the values of the anchor and other nodes
        self.nodeCoord = defaults.array(forKey: "nodeCoord") as? [[Float]] ?? nodeCoord
        self.nodeText = defaults.array(forKey: "nodeText") as? [String] ?? nodeText
        
        //////////////////////////////////////////////////
        
        // Set up Vision Model
        guard let selectedModel = try? VNCoreMLModel(for: Inceptionv3().model) else { // (Optional) This can be replaced with other models on https://developer.apple.com/machine-learning/
            fatalError("Could not load model. Ensure model has been drag and dropped (copied) to XCode Project from https://developer.apple.com/machine-learning/ . Also ensure the model is part of a target (see: https://stackoverflow.com/questions/45884085/model-is-not-part-of-any-target-add-the-model-to-a-target-to-enable-generation ")
        }
        
        // Set up Vision-CoreML Request
        let classificationRequest = VNCoreMLRequest(model: selectedModel, completionHandler: classificationCompleteHandler)
        classificationRequest.imageCropAndScaleOption = VNImageCropAndScaleOption.centerCrop // Crop from centre of images and scale to appropriate size.
        visionRequests = [classificationRequest]
        
        // Begin Loop to Update CoreML
        loopCoreMLUpdate()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        
        // Use gravity and heading Orientation
        configuration.worldAlignment = .gravityAndHeading
        
        // Enable plane detection
        configuration.planeDetection = .horizontal
        
        // Shows features points, userful for a better understanding of the application
        sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
        
        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }

    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
            // Do any desired updates to SceneKit here.
        }
    }
    
    // MARK: - Status Bar: Hide
    override var prefersStatusBarHidden : Bool {
        return true
    }
    
    func createNewBubbleParentNode(_ text : String) -> SCNNode {
        // Warning: Creating 3D Text is susceptible to crashing. To reduce chances of crashing; reduce number of polygons, letters, smoothness, etc.
        
        // TEXT BILLBOARD CONSTRAINT
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = SCNBillboardAxis.Y
        
        // BUBBLE-TEXT
        let bubble = SCNText(string: text, extrusionDepth: CGFloat(bubbleDepth))
        var font = UIFont(name: "Futura", size: 0.15)
        font = font?.withTraits(traits: .traitBold)
        bubble.font = font
        bubble.alignmentMode = kCAAlignmentCenter
        bubble.firstMaterial?.diffuse.contents = UIColor.orange
        bubble.firstMaterial?.specular.contents = UIColor.white
        bubble.firstMaterial?.isDoubleSided = true
        // bubble.flatness // setting this too low can cause crashes.
        bubble.chamferRadius = CGFloat(bubbleDepth)
        
        // BUBBLE NODE
        let (minBound, maxBound) = bubble.boundingBox
        let bubbleNode = SCNNode(geometry: bubble)
        // Centre Node - to Centre-Bottom point
        bubbleNode.pivot = SCNMatrix4MakeTranslation( (maxBound.x - minBound.x)/2, minBound.y, bubbleDepth/2)
        // Reduce default text size
        bubbleNode.scale = SCNVector3Make(0.2, 0.2, 0.2)
        
        // CENTRE POINT NODE
        let sphere = SCNSphere(radius: 0.005)
        sphere.firstMaterial?.diffuse.contents = UIColor.cyan
        let sphereNode = SCNNode(geometry: sphere)
        
        // BUBBLE PARENT NODE
        let bubbleNodeParent = SCNNode()
        bubbleNodeParent.addChildNode(bubbleNode)
        bubbleNodeParent.addChildNode(sphereNode)
        bubbleNodeParent.constraints = [billboardConstraint]
        
        return bubbleNodeParent
    }
    
    // MARK: - CoreML Vision Handling
    
    func loopCoreMLUpdate() {
        // Continuously run CoreML whenever it's ready. (Preventing 'hiccups' in Frame Rate)
        
        dispatchQueueML.async {
            // 1. Run Update.
            self.updateCoreML()
            
            // 2. Loop this function.
            self.loopCoreMLUpdate()
        }
        
    }
    
    func classificationCompleteHandler(request: VNRequest, error: Error?) {
        // Catch Errors
        if error != nil {
            print("Error: " + (error?.localizedDescription)!)
            return
        }
        guard let observations = request.results else {
            print("No results")
            return
        }
        
        // Get Classifications
        let classifications = observations[0...1] // top 2 results
            .flatMap({ $0 as? VNClassificationObservation })
            .map({ "\($0.identifier) \(String(format:"- %.2f", $0.confidence))" })
            .joined(separator: "\n")
        
        
        DispatchQueue.main.async {
            // Print Classifications
            print(classifications)
            print("--")
            
            // Display Debug Text on screen
            var debugText:String = ""
            debugText += classifications
            //self.debugTextView.text = debugText
            
            // Store the latest prediction
            var objectName:String = "…"
            objectName = classifications.components(separatedBy: "-")[0]
            objectName = objectName.components(separatedBy: ",")[0]
            self.latestPrediction = objectName
            
            //Notification of whether the anchor object is currently on the screen or not
            if (objectName==self.nodeText[0]){
                self.debugTextView.text = self.nodeText[0]
                self.anchorFound=true
            }else{
                self.debugTextView.text = debugText
                self.anchorFound=false
            }
        }
    }
    
    
    func updateCoreML() {
        ///////////////////////////
        // Get Camera Image as RGB
        let pixbuff : CVPixelBuffer? = (sceneView.session.currentFrame?.capturedImage)
        if pixbuff == nil { return }
        let ciImage = CIImage(cvPixelBuffer: pixbuff!)
        // Note: Not entirely sure if the ciImage is being interpreted as RGB, but for now it works with the Inception model.
        // Note2: Also uncertain if the pixelBuffer should be rotated before handing off to Vision (VNImageRequestHandler) - regardless, for now, it still works well with the Inception model.
        
        ///////////////////////////
        // Prepare CoreML/Vision Request
        let imageRequestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        // let imageRequestHandler = VNImageRequestHandler(cgImage: cgImage!, orientation: myOrientation, options: [:]) // Alternatively; we can convert the above to an RGB CGImage and use that. Also UIInterfaceOrientation can inform orientation values.
        
        ///////////////////////////
        // Run Image Request
        do {
            try imageRequestHandler.perform(self.visionRequests)
        } catch {
            print(error)
        }
        
    }

}

extension UIFont {
    // Based on: https://stackoverflow.com/questions/4713236/how-do-i-set-bold-and-italic-on-uilabel-of-iphone-ipad
    func withTraits(traits:UIFontDescriptorSymbolicTraits...) -> UIFont {
        let descriptor = self.fontDescriptor.withSymbolicTraits(UIFontDescriptorSymbolicTraits(traits))
        return UIFont(descriptor: descriptor!, size: 0)
    }
}
