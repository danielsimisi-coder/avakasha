import Cocoa
let c=CGContext(data:nil,width:1024,height:1024,bitsPerComponent:8,bytesPerRow:4096,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
c.setFillColor(CGColor(red:0.07,green:0.20,blue:0.22,alpha:1));c.addPath(CGPath(roundedRect:CGRect(x:30,y:30,width:964,height:964),cornerWidth:210,cornerHeight:210,transform:nil));c.fillPath()
c.setFillColor(CGColor(red:0.63,green:0.88,blue:0.77,alpha:1));c.addPath(CGPath(roundedRect:CGRect(x:218,y:200,width:588,height:624),cornerWidth:72,cornerHeight:72,transform:nil));c.fillPath()
c.setStrokeColor(CGColor(red:0.09,green:0.27,blue:0.27,alpha:1));c.setLineWidth(38);c.setLineCap(.round)
for (y,w) in [(690,390),(563,290),(436,170)] {c.move(to:CGPoint(x:313,y:y));c.addLine(to:CGPoint(x:313+w,y:y));c.strokePath()}
c.setLineWidth(43);c.setLineJoin(.round);c.move(to:CGPoint(x:550,y:330));c.addLine(to:CGPoint(x:610,y:275));c.addLine(to:CGPoint(x:745,y:430));c.strokePath()
let image=NSBitmapImageRep(cgImage:c.makeImage()!);try image.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
