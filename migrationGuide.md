# Migrate from V1 Guide

## Pregen wallet methods

Methods dealing with pregen wallets now use a simpler object-based notation to specify the type and identifier the wallet belongs to.

Old

```tsx
await para.createPregenWallet({
  pregenIdentifier: 'email@email.com',
  pregenIdentifierType: 'EMAIL'
});
```

New

```tsx
await para.createPregenWallet({ pregenId: { email: 'email@email.com' } });
```

( examples for phone, farc, telegram, twitter, discord, custom id )

## Phone numbers

Methods now accept phone numbers as single strings in international format without spaces or extra characters, i.e.: `+${number}` . If your UI deals in separated country codes and national phone numbers, you may use the exported `formatPhoneNumber` function to combine them into a correctly formatted string.

Old:

```tsx
const userExists = await para.checkIfUserExistsByPhone('3105551234', '1');
```

New:

```tsx
import { formatPhoneNumber } from '@getpara/web-sdk';

// checkIfUserExists is deprecated
await para.signUpOrLogIn({ auth: '+13105551234' });

await para.signUpOrLogIn({ auth: formatPhoneNumber('3105551234', '1') });

```

## Cancelable methods

(WEB/REACT/REACT-NATIVE ONLY) For methods that wait for user action, such as `waitForLogin`, you may now pass a callback that is invoked on each polling interval, as well as a callback to indicate whether the method should be canceled and another invoked upon cancelation.

```tsx
let i = 0;
await para.waitForLogin({
  isCanceled: () => popupWindow?.closed,
  onPoll: () => {
    console.log(`Waiting for login, polled ${++i} times...`)
  },
  onCancel: () => {
    console.log('Login canceled after popup window closed!');
  }
});
```

## New authentication methods

The primary methods for authenticating via phone or email address have been greatly simplified.  Simply call `signUpOrLogIn` using the email or phone number in question and then, depending on the state returned, present the corresponding UI and then call either `verifyNewAccount` followed by `waitForWalletCreation`, or `waitForLogin` .

( link to custom ui page for detailed info )

Old Email:

```tsx
const userExists = await para.checkIfUserExists({ email });

if (userExists) {
  const loginUrl = await para.initiateUserLogin({ email });
  
  const popupWindow = window?.open(loginUrl);
  
  await para.waitForPasskeyAndCreateWallet({ popupWindow });
} else {
	await para.createUser({ email });
	
	// show verification code input
}

// When verification code is entered:
try {
	const signupUrl = await para.verifyEmail({ verificationCode });
	  
	const popupWindow = window?.open(signupUrl);
	
	await para.waitForLoginAndSetup({ popupWindow });
} catch (e) {
	// handle incorrect code
}

```

New Email:

```tsx
const authState = await para.signUpOrLogIn({ auth: { email: emailAddress } });

switch (authState.stage) {
  case 'verify':
    // New user is already created for you
    
    // Display verification code input
    break;
  
  case 'login':
    // Login URLs are generated for you
    const { passkeyUrl, passkeyId, passwordUrl } = authState;
    
    // Display popup for the user's passkey or password entry, depending on your preference
    const popupWindow = window?.open(passkeyUrl);
   
    const { needsWallet } = await waitForLogin({
      isCanceled: () => popupWindow?.closed,
    })
    
    break;
 }
 
 // When verification code is entered:
 try {
   const authState = await para.verifyNewAccount({ verificationCode });
   
   // Signup URLs are generated for you
   const { passkeyUrl, passwordUrl } = authState;
   
   // Open popup with either URL depending on your preference
   const popupWindow = window?.open(passkeyUrl);
   
   const { needsWallet } = await waitForWalletCreation({
     isCanceled: () => popupWindow?.closed,
   })
 } catch (e) {
   // Handle error
 }
```

Old Phone:

```tsx
const userExists = await para.checkIfUserExistsByPhone({ phone, countryCode });

if (userExists) {
  const loginUrl = await para.initiateUserLoginForPhone({ phone, countryCode });
  
  const popupWindow = window?.open(loginUrl);
  
  await para.waitForPasskeyAndCreateWallet({ popupWindow });
} else {
	await para.createUserByPHone({ phone, countryCode });
	
	// show verification code input
}

// When verification code is entered:
try {
  const signupUrl = para.verifyPhone({ verificationCode });
	  	  
	const popupWindow = window?.open(signupUrl);
	
	await para.waitForLoginAndSetup({ popupWindow });
} catch (e) {
	// handle incorrect code
}

```

New Phone:

```tsx

import { formatPhoneNumber } from '@getpara/web-sdk';

const phoneIntl = formatPhoneNumber(phone, countryCode);

const authState = await para.signUpOrLogIn({ auth: { phone: phoneIntl} });

switch (authState.stage) {
  case 'verify':
    // New user is already created for you
    
    // Display verification code input
    break;
  
  case 'login':
    // Login URLs are generated for you
    const { passkeyUrl, passkeyId, passwordUrl } = authState;
    
    // Display popup for the user's passkey or password entry, depending on your preference
    const popupWindow = window?.open(passkeyUrl);
   
    const { needsWallet } = await waitForLogin({
      isCanceled: () => popupWindow?.closed,
    })
    
    break;
 }
 
 // When verification code is entered:
 try {
   const authState = await para.verifyNewAccount({ verificationCode });
   
   // Signup URLs are generated for you
   const { passkeyUrl, passwordUrl } = authState;
   
   // Open popup with either URL depending on your preference
   const popupWindow = window?.open(passkeyUrl);
   
   const { needsWallet } = await waitForWalletCreation({
     isCanceled: () => popupWindow?.closed,
   })
 } catch (e) {
   // Handle error
 }
 
 
```

## OAuth Authentication

OAuth authentication is simplified into a single method, `verifyOAuth` , which returns an AuthState object from which you can proceed as you would with a standard email signup or login.

Similarly, Farcaster logins are simplified into the method `verifyFarcaster` . As with Telegram sign-ins, these users bypass verifying via a one-time code but will not have an associated email address or phone number.

Old OAuth:

```tsx

const oAuthURL = await para.getOAuthURL({method});

window.open(oAuthURL, "oAuthPopup", "popup=true");

const { email, userExists } = await para.waitForOAuth();

if (!email) throw new Error("Email not found");

if (userExists) {
  const loginUrl = await para.initiateUserLogin({ email })
  
  const popupWindow = window.open(loginUrl, "loginPopup", "popup=true");
  
  await para.waitForLoginAndSetup({ popupWindow });
} else {
  const signupUrl = await para.getSetUpBiometricsURL({ authType: "email" });
  
  const popupWindow = window.open(loginUrl, "loginPopup", "popup=true");

  await para.waitForPasskeyAndCreateWallet({ popupWindow });
}
```

New OAuth:

( would still need to fetch oAuthUrl separately in swift/flutter )

```tsx
// Recommended to store window references in a React ref
let popupWindow;

const authState = await para.verifyOAuth({
  onOAuthUrl: oAuthUrl => {
    popupWindow = window?.open(oAuthUrl, 'OAuthPopup', 'popup=true');
  },
  isCanceled: () => popupWindow?.closed,
});

if (popupWindow && !popupWindow.closed) {
  popupWindow.close();
}

// Proceed as you would with a traditional email login, post-verification
switch (authState.stage) {
  case 'login':
    popupWindow = window?.open(authState.passkeyUrl, 'LoginPopup', 'popup=true');
    
    await para.waitForLogin({ isCanceled: () => popupWindow?.closed });
    
    break;
  case 'signup':
	  popupWindow = window?.open(authState.passkeyUrl, 'SignupPopup', 'popup=true');
    
    await para.waitForWalletCreation({ isCanceled: () => popupWindow?.closed });
    
    break;
}
```

Old Farcaster:

```tsx
const connectUri = await para.getFarcasterConnectURL();

// Display QR Code
setQrCodeValue(connectUri);

const { userExists, username: farcasterUsername } = await para.waitForFarcasterStatus();

if (userExists) {
  const loginUrl = await para.initiateUserLogin({ farcasterUsername })
  
  const popupWindow = window.open(loginUrl, "LoginPopup", "popup=true");
  
  await para.waitForLoginAndSetup({ popupWindow });
} else {
  const signupUrl = await para.getSetUpBiometricsURL({ authType: "farcaster" });
  
  const popupWindow = window.open(loginUrl, "SignupPopup", "popup=true");

  await para.waitForPasskeyAndCreateWallet({ popupWindow });
}
```

New Farcaster:

( would still need to fetch connectUri separately in swift/flutter )

```tsx
// Recommended to store window references in a React ref
let popupWindow;

const authState = await para.verifyFarcaster({
  onConnectUri: connectUri => {
    setQrCodeValue(connectUri);
  },
  // Check if user interaction has hidden/removed QR code
  isCanceled: () => qrCodeValueRef.current === ''
});

// Proceed as you would with a standard email login, post-verification
switch (authState.stage) {
  case 'login':
    popupWindow = window?.open(authState.passkeyUrl, 'LoginPopup', 'popup=true');
    
    await para.waitForLogin({ isCanceled: () => popupWindow?.closed });
    
    break;
  case 'signup':
	  popupWindow = window?.open(authState.passkeyUrl, 'SignupPopup', 'popup=true');
    
    await para.waitForWalletCreation({ isCanceled: () => popupWindow?.closed });
    
    break;
}
```

# V2 Custom UI Docs

If you want to build your own authentication UI in place of the Para Modal, we recommend using the provided React hooks. You may also invoke the `ParaWeb` authentication methods directly.

**Overview**

There are three stages for an authenticating user and three corresponding `AuthState` types that are returned from various authentication methods:

| Stage | Meaning | Applicable Methods |
| --- | --- | --- |
| `'verify'` | The user has entered their email or phone number and been sent a confimation code via email or SMS. Alternatively, they have logged in via an external wallet and need to sign a message to verify their ownership of the wallet. | `signUpOrLogIn`, `loginExternalWallet` |
| `'signup'`  | The user has verified their email, phone number, external wallet, or completed a third-party authentication and may now create a WebAuth passkey or password to secure their account.
 | `verifyNewAccount`,  `verifyExternalWallet`, `verifyOAuth`, `verifyTelegram`, `verifyFarcaster` |
| `'login'`  | The user has previously signed up and can now log in using their WebAuth passkey or password. | `signUpOrLogIn` , `loginExternalWallet` , `verifyOAuth` , `verifyTelegram`, `verifyFarcaster`  |

Below are the type definitions for each `AuthState` subtype:

```tsx
type AuthState = AuthStateVerify | AuthStateSignup | AuthStateLogin;

type AuthStateBase = {
  /**
   * The Para userId for the currently authenticating user.
   */
  userId: string;
  /**
   * The identity attestation for the current user, depending on their signup method:
   */
  auth:
    | { email: string }
    | { phone: `+${number}` }
    | { farcasterUsername: string }
    | { telegramUserId: string }
    | { externalWalletAddress: string }
  /**
   * For third-party authentication, additional useful metadata:
   */
  displayName?: string;
  pfpUrl?: string;
  username?: string;
  /**
   * For external wallet authentication, additional metadata:
   */
  externalWallet?: {
    address: string;
    type: 'EVM' | 'SOLANA' | 'COSMOS';
    provider?: string. // i.e. 'Metamask'
  };
}

type AuthStateVerify = AuthStateBase & {
  stage: "verify";
  /**
   * A unique string to be signed by the user's external wallet.
   */
  signatureVerificationMessage?: string;
};

type AuthStateSignup = AuthStateBase & {
  stage: "signup";
  /**
   * A Para Portal URL for creating a new WebAuth passkey. This URL is only present if you have enabled passkeys in your Developer Portal.
   * For compatibility and security, you should open this URL in a new window or tab.
   */
  passkeyUrl?: string;
  /**
   * The Para internal ID for the new passkey, if created. This is needed to complete the signup process for mobile devices.
   */
  passkeyId?: string;
  /**
   * A Para Portal URL for creating a new password. This URL is only present if you have enabled passwords in your Developer Portal.
   * You can open this URL in an iFrame or a new window or tab.
   */
  passwordUrl?: string;
};

type AuthStateLogin = AuthStateBase & {
  stage: "login";
  /**
   * A Para Portal URL for signing in with a WebAuth passkey. This URL is only present if the user has a previously created passkey.
   * For compatibility and security, you should open this URL in a new window or tab.
   */
  passkeyUrl?: string;
  /**
   * A Para Portal URL for creating a new password. This URL is only present if you have enabled passwords in your Developer Portal.
   * For compatibility and security, you should open this URL in a new window or tab.
   */
  passwordUrl?: string;
  /**
   * If the user has a previous passkey, an array of objects containing the associated `aaguid` and `useragent` fields.
   * You can format this to show a list of devices the user has previously logged in from.
   */
  biometricHints?: {
    aaguid: string;
    userAgent: string;
  }[];
};
```

You will most likely want to track the `AuthState` within your UI and update it for each method resolution. For example, you may want to store it in a dedicated context:

```tsx
import React from 'react';

const AuthStateContext = React.createContext<[
  AuthState | undefined,
  React.Dispatch<React.SetStateAction<AuthState | undefined>>
]>([undefined, () => {}]);

export function AuthStateProvider({ children }: React.PropsWithChildren) {
  const [authState, setAuthState] = React.useState<AuthState | undefined>();
  
	return {
		<AuthStateContext.Provider value={[authState, setAuthState]}>
		  {children}
		</AuthStateContext.Provider>
	};
}

export const useAuthState = () => React.useContext(AuthStateContext);
```

# **Code Samples**

## Phone or email address

### Sign up or log in

To authenticate a user via email or phone number, use the `useSignUpOrLogIn` hook. This mutation will either fetch the user with the provided authentication method and return an `AuthStateLogin` object, or create a new user and return an `AuthStateVerify` object.

- If the user already exists, you will need to open either the `passkeyUrl` or `passwordUrl` in a new window or tab, then invoke the `useWaitForLogin` mutation. This hook will wait until the user has completed the login process in the new window and then perform any needed setup.
- If the user is new, you will then need to display a verification code input and later invoke the `useVerifyNewAccount` mutation.

```tsx
import { useSignUpOrLogIn } from "@getpara/react-sdk";
import { useAuthState } from '@/hooks';

function AuthInput() {
  const { signUpOrLogIn, isLoading, isError } = useSignUpOrLogIn();
  const [authState, setAuthState] = useAuthState();
 
  const [authType, setAuthType] = useState<'email' | 'phone'>("email");
    // The determined authentication type from the input string

  const onSubmit = (identifier: string) => {
    signUpOrLogIn(
      {
        auth: authType === "email"
            ? { email: identifier }
            : { phone: identifier as `+${number}` },
      },
      {
        onSuccess: (authState) => {
          setAuthState(authState);
       
          switch (authState.stage) {
            case "verify":
              // Display verification code input
              break;
            case "login":
              const { passkeyUrl, passwordUrl } = authState;
              // Open a login URL in a new window or tab
              break;
          }
        },
        onError: (error) => {
          // Handle error
        },
      }
    );
  };

  // ...
}
```

### Verify new account

While in the `verify` stage, you will need to display an input for a six-digit code and a callback that invokes the `useVerifyNewAccount` hook. This will validate the one-time code and, if successful, will return an `AuthStateLogin` object. (The email or phone number previously entered is now stored, and will not need to be resupplied.)

```tsx
import { useVerifyNewAccount } from "@getpara/react-sdk";
import { useAuthState } from '@/hooks';

function VerifyOtp() {
  const { verifyNewAccount, isLoading, isError } = useVerifyNewAccount();
  const [_, setAuthState] = useAuthState();
  
  const [verificationCode, setVerificationCode] = useState('');
    // The six-digit code entered by the user

  const onSubmit = (verificationCode: string) => {
    verifyNewAccount(
      { verificationCode },
      {
        onSuccess: (authState) => {
          setAuthState(authState);
     
          const { passkeyUrl, passwordUrl } = authState;
         
          // Update your UI and prepare to log in the user
        },
        onError: (error) => {
          // Handle a mismatched code
        },
      }
    );
  };

  // ...
}
```

### Sign up a new user

After verification is complete, you will receive an `AuthStateSignup` object. Depending on your configuration, the `AuthStateLogin` will contain a Para URL for creating a WebAuth biometric passkey, a Para URL for creating a new password, or both. For compatibility and security, you will most likely want to open these URLs in a new popup window, and then immediately invoke the `useWaitForWalletCreation` hook. This will wait for the user to complete signup and then create a new wallet for each wallet type you have configured in the Para Developer Portal. If you would like more control over the signup process, you can also call the `useWaitForSignup` hook, which will resolve after signup but bypass automatic wallet provisioning. To cancel the process in response to UI events, you can pass the `isCanceled` callback. 

```tsx
import { useWaitForWalletCreation } from "@getpara/react-sdk";
import { useAuthState } from '@/hooks';

function Signup() {
  const popupWindow = React.useRef<Window | null>(null);
  const { waitForWalletCreation, isLoading, isError } = useWaitForWalletCreation();
  const [authState, setAuthState] = useAuthState();
  
  const onSelectSignupMethod = (chosenMethod: 'passkey' | 'password') => {
    const popupUrl = chosenMethod === 'passkey'
      ? authState.passkeyUrl!
      : authState.passwordUrl!
    
    popupWindow.current = window.open(popupUrl, `ParaSignup_${chosenMethod}`);
    
    waitForWalletCreation(
      {
        isCanceled: () => popupWindow.current?.closed,
      },
      {
        onSuccess: () => {
          // Handle successful signup and wallet provisioning
        },
        onError: (error) => {
          // Handle a canceled signup
        },
      }
    );
  };

  // ...
}

```

### Log in an existing user

Depending on your configuration, the `AuthStateLogin` will contain a Para URL for creating a WebAuth biometric passkey, a Para URL for creating a new password, or both. For compatibility and security, you will most likely want to open these URLs in a new popup window, and then immediately invoke the `useWaitForLogin` hook. This will wait for the user to complete the login process and resolve when it is finished. To cancel the process in response to UI events, you can pass the `isCanceled` callback. 

```tsx
import { useWaitForLogin } from "@getpara/react-sdk";
import { useAuthState } from '@/hooks';

function Login() {
  const popupWindow = React.useRef<Window | null>(null);
  const { waitForLogin, isLoading, isError } = useWaitForLogin();
  const [authState, setAuthState] = useAuthState();
  
  const onSelectLoginMethod = (chosenMethod: 'passkey' | 'password') => {
    const popupUrl = chosenMethod === 'passkey'
      ? authState.passkeyUrl!
      : authState.passwordUrl!;
    
    popupWindow.current = window.open(popupUrl, 'ParaLogin');
    
    waitForLogin(
      {
        isCanceled: () => popupWindow.current?.closed,
      },
      {
        onSuccess: (result) => {
          const { needsWallet } = result;
          
          if (needsWallet) {
            // Create wallet(s) for the user if needed
          } else {
            // Set up signed-in UI
          }
                 },
        onError: (error) => {
          // Handle a canceled login
        },
      }
    );
  };

  // ...
}
```

# Third-party authentication

For third-party authentication, the OTP verification step is bypassed. A successful authentication will advance your application to either the login or signup stage immediately.

## OAuth

Para supports OAuth 2.0 sign-ins via Google, Apple, Facebook, Discord, and X, provided the linked account has an email address set. Once a valid email account is fetched, the process is identical to that for email authentication, simply bypassing the one-time code verification step. To implement OAuth flow, use the `useVerifyOAuth` hook.

```tsx
import { OAuthMethod, useVerifyOAuth } from "@getpara/react-sdk";
import { useAuthState } from '@/hooks';

function OAuthLogin() {
  const popupWindow = React.useRef<Window | null>(null);
  const { verifyOAuth, isLoading, isError } = useVerifyOAuth();
  const [authState, setAuthState] = useAuthState();
  
  const onOAuthLogin = (method: OAuthMethod) => {
    verifyOAuth(
      {
        method,
        // Mandatory callback invoked when the OAuth URL is available.
        // You should open this URL in a new window or tab.
        onOAuthUrl: () => {
	        popupWindow.current = window.open(popupUrl, 'ParaOAuth');
        },
        isCanceled: () => popupWindow.current?.closed,
      },
      {
        onSuccess: (authState) => {
          setAuthState(authState);
          
          switch (authState.stage) {
            case 'signup':
              // New user: refer to 'Sign up a new user'
              break;
            case 'login':
              // Returning user: refer to 'Log in an existing user'
              break;
          };
        },
        onError: (error) => {
          // Handle a canceled OAuth verification
        },
      }
    );
  };

  // ...
}
```

## Telegram

Refer to Telegram’s documentation for information on authenticating via a bot. Once a Telegram authentication response is received, you can invoke the `useVerifyTelegram` hook to sign up or log in a user associated with the returned Telegram user ID. Users created via Telegram will *not* have an associated email address or phone number.

```tsx
import { useVerifyTelegram } from "@getpara/react-sdk";
import { useAuthState } from '@/hooks';

type TelegramAuthObject = {
  auth_date: number;
  first_name?: string;
  hash: string;
  id: number;
  last_name?: string;
  photo_url?: string;
  username?: string;
};

function TelegramLogin() {
  const popupWindow = React.useRef<Window | null>(null);
  const { verifyTelegram, isLoading, isError } = useVerifyTelegram();
  const [authState, setAuthState] = useAuthState();
  
  const onTelegramResponse = (response: telegramAuthObject) => {
    waitForLogin(
      { telegramAuthObject },
      {
        onSuccess: (authState) => {
          setAuthState(authState);
          
          switch (authState.stage) {
            case 'signup':
              // New user: refer to 'Sign up a new user'
              break;
            case 'login':
              // Returning user: refer to 'Log in an existing user'
              break;
          };
        },
        onError: (error) => {
          // Handle a failed Telegram verification
        },
      }
    );
  };

  // ...
}
```

### Farcaster

Refer to Farcaster’s documentation on how to sign in via Warpcast. To include this authentication method, use the `useVerifyFarcaster` hook. The hook will supply a Farcaster Connect URI, which should be displayed to your users as a QR code. Like with Telegram, users created via Farcaster will *not* have an associated email address or phone number.

```tsx
import { useVerifyFarcaster } from "@getpara/react-sdk";
import { useAuthState } from '@/hooks';

function FarcasterLogin() {
  const { verifyTelegram, isLoading, isError } = useVerifyFarcaster();
  const [authState, setAuthState] = useAuthState();
  
  const [farcasterConnectUri, setFarcasterConnectUri] = useState<string | null>(null);
  const isCanceled = React.useRef(false);
  
  useEffect(() => {
    isCanceled.current = !farcasterConnectUri;
  }, [farcasterConnectUri]);
  
  const onClickCancelButton = () => {
    setFarcasterConnectUri(null);
  }
  
  const onClickFarcasterLoginButton = () => {
    verifyFarcaster(
      {
        // Mandatory callback invoked when the OAuth URL is available.
        // You should display the URI as a QR code.
        onConnectUri: connectUri => {
	        setFarcasterConnectUri(connectUri);
	      },
	      // Cancel the login process if the URI is unset	
	      isCanceled: () => isCanceled.current,
	    },
      {
        onSuccess: (authState) => {
          setAuthState(authState);
          
          switch (authState.stage) {
            case 'signup':
              // New user: refer to 'Sign up a new user'
              break;
            case 'login':
              // Returning user: refer to 'Log in an existing user'
              break;
          };
        },
        onError: (error) => {
          // Handle a failed Telegram verification
        },
      }
    );
  };

  // ...
}
```

Note that  passkeyId in the auth state is the same as the biometricId that we have in v1
iOS should be using native passkey flows!