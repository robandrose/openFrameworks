/*
 *  AVFoundationVideoGrabber.mm
 */

#include "AVFoundationVideoGrabber.h"

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include "ofxiPhoneExtras.h"

//#if __IPHONE_OS_VERSION_MIN_REQUIRED > __IPHONE_3_2

#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>

#if defined  __arm__


@implementation iPhoneVideoGrabber

@synthesize captureSession	= _captureSession;

#pragma mark -
#pragma mark Initialization
- (id)init {
	self = [super init];
//	if (self) {
//		/*We initialize some variables (they might be not initialized depending on what is commented or not)*/
//		self.imageView = nil;
//		self.prevLayer = nil;
//		self.customLayer = nil;
//	}
	bInitCalled = false;
	grabberPtr=NULL;
	device=0;
	return self;
}

- (void)initCapture:(int)framerate capWidth:(int)w capHeight:(int)h{
	/*We setup the input*/
	/*captureInput						= [AVCaptureDeviceInput 
										  deviceInputWithDevice:[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] 
										  error:nil];*/
	
	captureInput						= [AVCaptureDeviceInput 
										   deviceInputWithDevice:[[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] objectAtIndex:device]
										   error:nil];
										  	
	/*We setupt the output*/
	AVCaptureVideoDataOutput *captureOutput = [[AVCaptureVideoDataOutput alloc] init];
	/*While a frame is processes in -captureOutput:didOutputSampleBuffer:fromConnection: delegate methods no other frames are added in the queue.
	 If you don't want this behaviour set the property to NO */
	captureOutput.alwaysDiscardsLateVideoFrames = YES; 
	/*We specify a minimum duration for each frame (play with this settings to avoid having too many frames waiting
	 in the queue because it can cause memory issues). It is similar to the inverse of the maximum framerate.
	 In this example we set a min frame duration of 1/10 seconds so a maximum framerate of 10fps. We say that
	 we are not able to process more than 10 frames per second.*/
	captureOutput.minFrameDuration = CMTimeMake(1, framerate);
	
	/*We create a serial queue to handle the processing of our frames*/
	dispatch_queue_t queue;
	queue = dispatch_queue_create("cameraQueue", NULL);
	[captureOutput setSampleBufferDelegate:self queue:queue];
	dispatch_release(queue);
	
	// Set the video output to store frame in BGRA (It is supposed to be faster)
	NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey; 
	NSNumber* value = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA]; 

	NSDictionary* videoSettings = [NSDictionary dictionaryWithObject:value forKey:key]; 
	[captureOutput setVideoSettings:videoSettings]; 

	/*And we create a capture session*/	
	self.captureSession = [[AVCaptureSession alloc] init];
	
	[self.captureSession beginConfiguration]; 
	
	NSString * preset = AVCaptureSessionPresetMedium;
	width	= 480;
	height	= 360;	
		
	if( w == 640 && h == 480 ){
		preset = AVCaptureSessionPreset640x480;
		width	= w;
		height	= h;
	}
	else if( w == 1280 && h == 720 ){
		preset = AVCaptureSessionPreset1280x720;
		width	= w;
		height	= h;		
	}

	[self.captureSession setSessionPreset:preset]; 
	
	/*We add input and output*/
	[self.captureSession addInput:captureInput];
	[self.captureSession addOutput:captureOutput];
	
	[self.captureSession commitConfiguration];		
	[self.captureSession startRunning];

	bInitCalled = true;
	
}

-(void) startCapture{

	if( !bInitCalled ){
		[self initCapture:30 capWidth:480 capHeight:320];
	}

	[self.captureSession startRunning];
	
	[captureInput.device lockForConfiguration:nil];
	
	//if( [captureInput.device isExposureModeSupported:AVCaptureExposureModeAutoExpose] ) [captureInput.device setExposureMode:AVCaptureExposureModeAutoExpose ];
	if( [captureInput.device isFocusModeSupported:AVCaptureFocusModeAutoFocus] )	[captureInput.device setFocusMode:AVCaptureFocusModeAutoFocus ];

}

-(void) lockExposureAndFocus{

	[captureInput.device lockForConfiguration:nil];
	
	//if( [captureInput.device isExposureModeSupported:AVCaptureExposureModeLocked] ) [captureInput.device setExposureMode:AVCaptureExposureModeLocked ];
	if( [captureInput.device isFocusModeSupported:AVCaptureFocusModeLocked] )	[captureInput.device setFocusMode:AVCaptureFocusModeLocked ];
	
	
}

-(void)stopCapture{
	[self.captureSession stopRunning];
}

-(CGImageRef)getCurrentFrame{
	return currentFrame;
}

-(void)listDevices{
	NSArray * devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
	int i=0;
	for (AVCaptureDevice *device in devices){
		 cout<<"Device "<<i<<": "<<ofxNSStringToString(device.localizedName)<<endl;
		i++;
    }
}
-(void)setDevice:(int)_device{
	device = _device;
}

#pragma mark -
#pragma mark AVCaptureSession delegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput 
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer 
	   fromConnection:(AVCaptureConnection *)connection 
{ 
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
	CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer); 
	/*Lock the image buffer*/
	CVPixelBufferLockBaseAddress(imageBuffer,0); 

	/*Get information about the image*/
	uint8_t *baseAddress	= (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer); 
	size_t bytesPerRow		= CVPixelBufferGetBytesPerRow(imageBuffer); 
	size_t widthIn			= CVPixelBufferGetWidth(imageBuffer); 
	size_t heightIn			= CVPixelBufferGetHeight(imageBuffer);  
		
	/*Create a CGImageRef from the CVImageBufferRef*/
	
	CGColorSpaceRef colorSpace	= CGColorSpaceCreateDeviceRGB(); 
	
	CGContextRef newContext		= CGBitmapContextCreate(baseAddress, widthIn, heightIn, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
	CGImageRef newImage			= CGBitmapContextCreateImage(newContext); 

	CGImageRelease(currentFrame);	
	currentFrame = CGImageCreateCopy(newImage);		
		
	/*We release some components*/
	CGContextRelease(newContext); 
	CGColorSpaceRelease(colorSpace);

	/*We relase the CGImageRef*/
	CGImageRelease(newImage);
		
	/*We unlock the  image buffer*/
	CVPixelBufferUnlockBaseAddress(imageBuffer,0);
	
	if(grabberPtr != NULL)
		grabberPtr->updatePixelsCB(currentFrame); // this is an issue if the class is deleted before the object is removed on quit etc.
	
	[pool drain];
} 

#pragma mark -
#pragma mark Memory management

- (void)dealloc {
    [super dealloc];
}

- (void)eraseGrabberPtr {
	grabberPtr = NULL;
}

@end


AVFoundationVideoGrabber::AVFoundationVideoGrabber(){
	fps		= 30;
	grabber = [iPhoneVideoGrabber alloc];
	pixels	= NULL;
	
	internalGlDataType = GL_RGB;
	newFrame=false;
}

AVFoundationVideoGrabber::~AVFoundationVideoGrabber(){
	[grabber eraseGrabberPtr];
	[grabber stopCapture];
	clear();
}
		
void AVFoundationVideoGrabber::clear(){
	if( pixels != NULL ){
		free(pixels);
		pixels = NULL;
	}
	//tex.clear();
	free(pixelsTmp);
}

void AVFoundationVideoGrabber::setCaptureRate(int capRate){
	fps = capRate;
}

void AVFoundationVideoGrabber::initGrabber(int w, int h){

	[grabber initCapture:fps capWidth:w capHeight:h];
	grabber->grabberPtr = this;
	
	width	= grabber->width;
	height	= grabber->height;
	
	clear();
	
	pixelsTmp	= (GLubyte *) malloc(width * height * 4);

	if(internalGlDataType == GL_RGB) {
		//tex.allocate(width, height, GL_RGB);
		pixels = (GLubyte *) malloc(width * height * 3);//new unsigned char[width * width * 3];//memset(pixels, 0, width*height*3);
	}
	else if(internalGlDataType == GL_RGBA) {
		//tex.allocate(width, height, GL_RGBA);
		pixels = (GLubyte *) malloc(width * height * 4);
	}
	else if(internalGlDataType == GL_BGRA) {
		//tex.allocate(width, height, GL_BGRA);
		pixels = (GLubyte *) malloc(width * height * 4);
	}
		
	[grabber startCapture];
	
	bUpdateTex = true;
	newFrame=false;
}

void AVFoundationVideoGrabber::updatePixelsCB( CGImageRef & ref ){
	bUpdateTex = true;//ofxiPhoneCGImageToPixels(ref, pixels);
	
	CGContextRef spriteContext;
		
	// Uses the bitmap creation function provided by the Core Graphics framework. 
	spriteContext = CGBitmapContextCreate(pixelsTmp, width, height, CGImageGetBitsPerComponent(ref), width * 4, CGImageGetColorSpace(ref), kCGImageAlphaPremultipliedLast);
	
	CGContextDrawImage(spriteContext, CGRectMake(0.0, 0.0, (CGFloat)width, (CGFloat)height), ref);
	CGContextRelease(spriteContext);
	
	/*
	 // averaging around 3300ms per 100reps
	 long then = ofGetElapsedTimeMillis();
	 for (int N=0; N<100; N++){
	 int j = 0;
	 for(int k = 0; k < totalSrcBytes; k+= bytesPerPixel ){
	 pixels[j  ] = pixelsTmp[k  ];
	 pixels[j+1] = pixelsTmp[k+1];
	 pixels[j+2] = pixelsTmp[k+2];
	 j+=3;
	 }
	 
	 }
	 long now = ofGetElapsedTimeMillis();
	 printf("elapsed = %d\n", (now-then));
	 */
	
	// Step through both source and destination 4 bytes at a time.
	// But reset the destination pointer by shifting it backwards 1 byte each time. 
	// Effectively: 4 steps forward, 1 step back each time through the loop. 
	// on average, around 1750ms for 100 reps // GOOD
	
	if(internalGlDataType == GL_RGB)
	{
		unsigned int *isrc4 = (unsigned int *)pixelsTmp;
		unsigned int *idst3 = (unsigned int *)pixels;
		unsigned int *ilast4 = &isrc4[width*height-1];
		while (isrc4 < ilast4){
			*(idst3++) = *(isrc4++);
			idst3 = (unsigned int *) (((unsigned char *) idst3) - 1);
		}
	}
	else if(internalGlDataType == GL_RGBA || internalGlDataType == GL_BGRA)
	{
		unsigned int *isrc4 = (unsigned int *)pixelsTmp;
		unsigned int *idst4 = (unsigned int *)pixels;
		unsigned int *ilast4 = &isrc4[width*height-1];
		while (isrc4 < ilast4){
			*(idst4++) = *(isrc4++);
		}
	}
	
	newFrame=true;
}

bool AVFoundationVideoGrabber::isFrameNew()
{
	if(newFrame) {
		newFrame=false;
		return true;
	}
	else
		return false;
}
		
void AVFoundationVideoGrabber::draw(float x, float y){
	draw(x, y, width, height);
}

void AVFoundationVideoGrabber::draw(float x, float y, float w, float h){
	if( bUpdateTex ){
		//tex.loadData(pixels, w, h, internalGlDataType);
		bUpdateTex = false;
	}
	//tex.draw(x, y, w, h);
}

void AVFoundationVideoGrabber::listDevices() {
	[grabber listDevices];
}

void AVFoundationVideoGrabber::setDevice(int deviceID) {
	[grabber setDevice:deviceID];
}

void AVFoundationVideoGrabber::setPixelFormat(ofPixelFormat PixelFormat) {
	if(PixelFormat == OF_PIXELS_RGB)
		internalGlDataType = GL_RGB;
	else if(PixelFormat == OF_PIXELS_RGBA)
		internalGlDataType = GL_RGBA;
	else if(PixelFormat == OF_PIXELS_BGRA)
		internalGlDataType = GL_BGRA;
}

#endif	// (__arm__) compile only for ARM
//
//#else   // compile for 4.0+
//
//#warning "skipping AVFoundationVideoGrabber compilation because you need > 3.2 iOS SDK"
//
//#endif
