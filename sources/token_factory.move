module dynexus_forge::token_factory {

    use std::option;
    use std::signer::address_of;
    use std::string::String;
    use std::vector;
    use aptos_std::table::{Self, Table};
    use aptos_std::table_with_length::{Self, TableWithLength};
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{
        Self,
        FungibleAsset,
        MintRef,
        TransferRef,
        BurnRef,
        Metadata
    };
    use aptos_framework::object::{Self, ExtendRef, Object, address_to_object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;

    //
    // Constants
    //

    /// Contract addresss
    const CA: address = @dynexus_forge;
    /// Token creation seed
    const TOKEN_SEED: vector<u8> = b"DYNEXUS";
    /// Token factory object creation seed
    const TOKEN_FACTORY_OBJECT_SEED: vector<u8> = b"DYNEXUS_FORGE_OWNER";
    /// Max token decimal
    const MAX_DECIMAL: u8 = 8;
    /// Max token uri length
    const MAX_URI_LENGTH: u64 = 512;
    /// Max tokens returned by a single paginated view call
    const MAX_PAGE_SIZE: u64 = 100;

    //
    // Errors
    //

    /// Token already exists in the registry.
    const E_TOKEN_ALREADY_EXISTS: u64 = 1;

    /// User is not the owner and is not authorized to perform this action.
    const E_NOT_AN_OWNER: u64 = 6;

    /// Token not exists in the registry.
    const E_TOKEN_NOT_EXISTS: u64 = 7;

    /// Token deciaml should less then 8
    const E_INVALID_TOKEN_DECIMAL: u64 = 9;

    /// Token uri length should less then 512
    const E_INVALID_URI_LENGTH: u64 = 10;

    /// Token address are same
    const E_INVALID_TOKEN_ADDRESS: u64 = 11;

    /// User has insufficient balance of dynexus.
    const E_INSUFFICIENT_DYANEXUS_BALANCE: u64 = 12;

    /// User requested for early faucet
    const E_EARLY_FAUCET: u64 = 13;

    /// New config value is the same as the current one.
    const E_SAME_VALUE: u64 = 14;

    /// DYNEXUS token has not been set by the admin yet.
    const E_DYNEXUS_TOKEN_NOT_SET: u64 = 15;

    /// Amount must be greater than zero.
    const E_ZERO_AMOUNT: u64 = 16;

    /// Caller is not an approved DYNEXUS minter.
    const E_NOT_A_MINTER: u64 = 17;

    /// Address is already an approved DYNEXUS minter.
    const E_ALREADY_A_MINTER: u64 = 18;

    //
    // Structs
    //

    struct TokenRegistry has key {
        //
        dynexus_token: address,

        // Admin controls
        admin: address,
        /// Flat fee charged per token creation, in DYNEXUS base units.
        plateform_fee_rate: u64,

        // Faucet
        faucet_period: u64,
        faucet_amount: u64,
        faucet_history: Table<address, u64>,

        // Statistics
        /// Number of tokens created through the factory.
        total_users: u64,

        // Token index (for listing in frontends)
        all_tokens: TableWithLength<u64, address>,
        creator_tokens: Table<address, vector<address>>,

        /// Contracts allowed to mint DYNEXUS (e.g. the Dynexus Core emissions minter).
        minters: vector<address>,

        // extending object signer
        extend_ref: ExtendRef
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct ManageFungibleAsset has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
        creator: address
    }

    //
    // Events
    //

    #[event]
    struct TokenCreated has drop, store {
        creator: address,
        token_address: address,
        timestamp: u64
    }

    #[event]
    struct FaucetDynexus has drop, store {
        user: address,
        amount: u64,
        next_period: u64
    }

    #[event]
    struct TokenBurned has drop, store {
        owner: address,
        token_address: address,
        amount: u64
    }

    #[event]
    struct MinterUpdated has drop, store {
        minter: address,
        approved: bool
    }

    //
    // Inttialize Function
    //

    /// Initializes the Token Factory module
    ///
    /// # Parameters
    /// - `admin`: signer of the admin deploying the token factory
    fun init_module(admin: &signer) {
        let admin_addr = address_of(admin);
        let constructor_ref =
            &object::create_named_object(admin, TOKEN_FACTORY_OBJECT_SEED);
        let obj_signer = &object::generate_signer(constructor_ref);
        let extend_ref = object::generate_extend_ref(constructor_ref);

        move_to(
            obj_signer,
            TokenRegistry {
                admin: admin_addr,
                total_users: 0,
                plateform_fee_rate: 5, // DYNEXUS token
                faucet_period: 600, // In seconds
                faucet_amount: 5,
                faucet_history: table::new(),
                all_tokens: table_with_length::new(),
                creator_tokens: table::new(),
                minters: vector::empty(),
                extend_ref,
                dynexus_token: @0x0
            }
        );
    }

    //
    // Admin
    //

    public entry fun set_dynexus_token(
        owner: &signer, new_address: address
    ) acquires TokenRegistry {
        let registry = borrow_registry_as_admin_mut(owner);
        assert!(registry.dynexus_token != new_address, E_INVALID_TOKEN_ADDRESS);
        assert!(exists<ManageFungibleAsset>(new_address), E_TOKEN_NOT_EXISTS);
        registry.dynexus_token = new_address;
    }

    public entry fun set_dynexus_plateform_fee_rate(
        owner: &signer, new_fee: u64
    ) acquires TokenRegistry {
        let registry = borrow_registry_as_admin_mut(owner);
        assert!(registry.plateform_fee_rate != new_fee, E_SAME_VALUE);
        registry.plateform_fee_rate = new_fee;
    }

    public entry fun set_dynexus_faucet_period(
        owner: &signer, new_period: u64
    ) acquires TokenRegistry {
        let registry = borrow_registry_as_admin_mut(owner);
        assert!(registry.faucet_period != new_period, E_SAME_VALUE);
        registry.faucet_period = new_period;
    }

    public entry fun set_dynexus_faucet_amount(
        owner: &signer, new_amount: u64
    ) acquires TokenRegistry {
        let registry = borrow_registry_as_admin_mut(owner);
        assert!(registry.faucet_amount != new_amount, E_SAME_VALUE);
        registry.faucet_amount = new_amount;
    }

    /// Approve a contract address to mint DYNEXUS through `mint_dynexus`.
    public entry fun add_dynexus_minter(owner: &signer, minter: address) acquires TokenRegistry {
        let registry = borrow_registry_as_admin_mut(owner);
        assert!(!registry.minters.contains(&minter), E_ALREADY_A_MINTER);
        registry.minters.push_back(minter);
        event::emit(MinterUpdated { minter, approved: true });
    }

    public entry fun remove_dynexus_minter(owner: &signer, minter: address) acquires TokenRegistry {
        let registry = borrow_registry_as_admin_mut(owner);
        let (found, index) = registry.minters.index_of(&minter);
        assert!(found, E_NOT_A_MINTER);
        registry.minters.remove(index);
        event::emit(MinterUpdated { minter, approved: false });
    }

    //
    // Faucet & DYNEXUS minting
    //

    public entry fun faucet_dynexus(user: &signer) acquires TokenRegistry, ManageFungibleAsset {
        let user_addr = address_of(user);

        let registry = borrow_global_mut<TokenRegistry>(get_token_factory_object_addr());
        assert!(registry.dynexus_token != @0x0, E_DYNEXUS_TOKEN_NOT_SET);
        let current_time = timestamp::now_seconds();

        if (registry.faucet_history.contains(user_addr)) {
            let next_allowed = *registry.faucet_history.borrow(user_addr);
            assert!(current_time >= next_allowed, E_EARLY_FAUCET)
        };

        let faucet_amount = registry.faucet_amount;
        let manage_dynexus = borrow_global<ManageFungibleAsset>(registry.dynexus_token);
        let dynexus = fungible_asset::mint(&manage_dynexus.mint_ref, faucet_amount);
        primary_fungible_store::deposit(user_addr, dynexus);

        let next_period = current_time + registry.faucet_period;
        registry.faucet_history.upsert(user_addr, next_period);

        event::emit(FaucetDynexus { user: user_addr, amount: faucet_amount, next_period })
    }

    /// Mint DYNEXUS for an approved minter contract (used for protocol emissions).
    public fun mint_dynexus(
        minter: &signer, amount: u64
    ): FungibleAsset acquires TokenRegistry, ManageFungibleAsset {
        assert!(amount > 0, E_ZERO_AMOUNT);
        let registry = borrow_global<TokenRegistry>(get_token_factory_object_addr());
        assert!(registry.minters.contains(&address_of(minter)), E_NOT_A_MINTER);
        assert!(registry.dynexus_token != @0x0, E_DYNEXUS_TOKEN_NOT_SET);
        let manage_dynexus = borrow_global<ManageFungibleAsset>(registry.dynexus_token);
        fungible_asset::mint(&manage_dynexus.mint_ref, amount)
    }

    //
    // Token Creation & Management
    //

    /// Creates a custom fungible token in the DYNA ecosystem.
    ///
    /// # Parameters
    /// - `creator`: signer of the token creator
    /// - `name`: Full name of the token (max 32 chars, framework limit)
    /// - `symbol`: Short symbol (max 32 chars, framework limit)
    /// - `decimals`: Decimal precision (max `MAX_DECIMAL`)
    /// - `inital_supply`: Initial amount of tokens to mint to creator
    /// - `icon_uri`: Link to token icon (max `MAX_URI_LENGTH`)
    /// - `project_uri`: Project website or metadata link (max `MAX_URI_LENGTH`)
    ///
    /// Charges `plateform_fee_rate` DYNEXUS to every creator except the admin.
    ///
    /// # Aborts With
    /// - `E_TOKEN_ALREADY_EXISTS` if this creator already made a token with same name/symbol
    /// - `E_INVALID_TOKEN_DECIMAL` / `E_INVALID_URI_LENGTH` for invalid parameters
    /// - `E_INSUFFICIENT_DYANEXUS_BALANCE` if creator cannot pay the fee
    public entry fun create_token(
        creator: &signer,
        name: String,
        symbol: String,
        decimals: u8,
        inital_supply: u64,
        icon_uri: String,
        project_uri: String
    ) acquires TokenRegistry {
        let creator_addr = address_of(creator);
        let registry = borrow_global_mut<TokenRegistry>(get_token_factory_object_addr());

        assert!(decimals <= MAX_DECIMAL, E_INVALID_TOKEN_DECIMAL);
        assert!(
            icon_uri.length() <= MAX_URI_LENGTH
                && project_uri.length() <= MAX_URI_LENGTH,
            E_INVALID_URI_LENGTH
        );

        let token_seed = create_token_seed(&name, &symbol);
        let token_address = object::create_object_address(&creator_addr, token_seed);
        assert!(!exists<ManageFungibleAsset>(token_address), E_TOKEN_ALREADY_EXISTS);

        // Apply Charges
        if (creator_addr != registry.admin && registry.plateform_fee_rate > 0) {
            assert!(registry.dynexus_token != @0x0, E_DYNEXUS_TOKEN_NOT_SET);
            let dynexus_metadata = address_to_object<Metadata>(registry.dynexus_token);
            let balance = primary_fungible_store::balance(
                creator_addr, dynexus_metadata
            );
            assert!(
                balance >= registry.plateform_fee_rate,
                E_INSUFFICIENT_DYANEXUS_BALANCE
            );
            primary_fungible_store::transfer(
                creator,
                dynexus_metadata,
                registry.admin,
                registry.plateform_fee_rate
            );
        };

        let constuctor_ref = object::create_named_object(creator, token_seed);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constuctor_ref,
            option::none(),
            name,
            symbol,
            decimals,
            icon_uri,
            project_uri
        );

        let mint_ref = fungible_asset::generate_mint_ref(&constuctor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(&constuctor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(&constuctor_ref);
        let token_signer = object::generate_signer(&constuctor_ref);

        if (inital_supply > 0) {
            let fa = fungible_asset::mint(&mint_ref, inital_supply);
            primary_fungible_store::deposit(creator_addr, fa);
        };

        move_to(
            &token_signer,
            ManageFungibleAsset { mint_ref, burn_ref, transfer_ref, creator: creator_addr }
        );

        // Index
        registry.all_tokens.add(registry.total_users, token_address);
        registry.total_users += 1;
        if (!registry.creator_tokens.contains(creator_addr)) {
            registry.creator_tokens.add(creator_addr, vector::empty());
        };
        registry.creator_tokens.borrow_mut(creator_addr).push_back(token_address);

        event::emit(
            TokenCreated {
                creator: creator_addr,
                token_address,
                timestamp: timestamp::now_seconds()
            }
        );
    }

    /// Mints additional supply of a DYNA-based token to a user
    ///
    /// # Parameters
    /// - `owner`: signer of token owner/creator
    /// - `to`: address to receive minted tokens
    /// - `token_address`: address of the token to mint
    /// - `amount`: quantity to mint
    ///
    /// # Aborts With
    /// - `E_NOT_AN_OWNER` if caller is not token creator
    public entry fun mint_token(
        owner: &signer,
        to: address,
        token_address: address,
        amount: u64
    ) acquires ManageFungibleAsset {
        let owner_addr = address_of(owner);

        // Check `ManageFungibleAsset` exist
        assert!(exists<ManageFungibleAsset>(token_address), E_NOT_AN_OWNER);

        // Check ownership
        let manage_auth = borrow_global<ManageFungibleAsset>(token_address);
        assert!(manage_auth.creator == owner_addr, E_NOT_AN_OWNER);

        // Transfer minted FA
        let token = fungible_asset::mint(&manage_auth.mint_ref, amount);
        primary_fungible_store::deposit_with_ref(&manage_auth.transfer_ref, to, token);
    }

    /// Burns `amount` of a factory token from the caller's own primary store.
    public entry fun burn_token(
        owner: &signer, token_address: address, amount: u64
    ) acquires ManageFungibleAsset {
        assert!(amount > 0, E_ZERO_AMOUNT);
        assert!(exists<ManageFungibleAsset>(token_address), E_TOKEN_NOT_EXISTS);
        let owner_addr = address_of(owner);
        let manage_auth = borrow_global<ManageFungibleAsset>(token_address);
        let metadata = address_to_object<Metadata>(token_address);
        let store = primary_fungible_store::primary_store(owner_addr, metadata);
        fungible_asset::burn_from(&manage_auth.burn_ref, store, amount);
        event::emit(TokenBurned { owner: owner_addr, token_address, amount });
    }

    //
    // Helper Functions
    //

    /// Create token seed
    fun create_token_seed(name: &String, symbol: &String): vector<u8> {
        let seed = TOKEN_SEED;
        seed.append(*name.bytes());
        seed.append(*symbol.bytes());
        seed
    }

    /// Borrow the registry mutably, aborting unless `owner` is the admin.
    inline fun borrow_registry_as_admin_mut(owner: &signer): &mut TokenRegistry {
        let registry = borrow_global_mut<TokenRegistry>(get_token_factory_object_addr());
        assert!(registry.admin == address_of(owner), E_NOT_AN_OWNER);
        registry
    }

    //
    // View functions
    //

    #[view]
    /// Returns (dynexus_token, admin, platform_fee, faucet_period, faucet_amount, total_tokens)
    public fun get_dynexus_config(): (address, address, u64, u64, u64, u64) acquires TokenRegistry {
        let config = borrow_global<TokenRegistry>(get_token_factory_object_addr());
        (
            config.dynexus_token,
            config.admin,
            config.plateform_fee_rate,
            config.faucet_period,
            config.faucet_amount,
            config.total_users
        )
    }

    #[view]
    public fun get_token_factory_object_addr(): address {
        object::create_object_address(&CA, TOKEN_FACTORY_OBJECT_SEED)
    }

    #[view]
    public fun get_token_fa_address(
        creator: address, name: String, symbol: String
    ): address {
        let seed = create_token_seed(&name, &symbol);
        object::create_object_address(&creator, seed)
    }

    #[view]
    /// Timestamp (seconds) at which `user` may next claim from the faucet; 0 if never claimed.
    public fun get_next_faucet_time(user: address): u64 acquires TokenRegistry {
        let registry = borrow_global<TokenRegistry>(get_token_factory_object_addr());
        if (registry.faucet_history.contains(user)) {
            *registry.faucet_history.borrow(user)
        } else { 0 }
    }

    #[view]
    /// Tokens created through the factory, oldest first. `limit` is capped at `MAX_PAGE_SIZE`.
    public fun get_tokens(offset: u64, limit: u64): vector<address> acquires TokenRegistry {
        let registry = borrow_global<TokenRegistry>(get_token_factory_object_addr());
        let total = registry.all_tokens.length();
        let page = vector::empty<address>();
        if (offset >= total) return page;
        if (limit > MAX_PAGE_SIZE) {
            limit = MAX_PAGE_SIZE
        };
        let end =
            if (limit > total - offset) { total }
            else {
                offset + limit
            };
        let i = offset;
        while (i < end) {
            page.push_back(*registry.all_tokens.borrow(i));
            i += 1;
        };
        page
    }

    #[view]
    public fun get_tokens_by_creator(creator: address): vector<address> acquires TokenRegistry {
        let registry = borrow_global<TokenRegistry>(get_token_factory_object_addr());
        if (registry.creator_tokens.contains(creator)) {
            *registry.creator_tokens.borrow(creator)
        } else {
            vector::empty()
        }
    }

    #[view]
    public fun is_factory_token(token_address: address): bool {
        exists<ManageFungibleAsset>(token_address)
    }

    #[view]
    /// Returns (creator, name, symbol, decimals, supply, icon_uri, project_uri)
    public fun get_token_info(
        token_address: address
    ): (address, String, String, u8, u128, String, String) acquires ManageFungibleAsset {
        assert!(exists<ManageFungibleAsset>(token_address), E_TOKEN_NOT_EXISTS);
        let creator = borrow_global<ManageFungibleAsset>(token_address).creator;
        let metadata: Object<Metadata> = address_to_object<Metadata>(token_address);
        let supply = fungible_asset::supply(metadata);
        (
            creator,
            fungible_asset::name(metadata),
            fungible_asset::symbol(metadata),
            fungible_asset::decimals(metadata),
            if (supply.is_some()) {
                supply.destroy_some()
            } else { 0 },
            fungible_asset::icon_uri(metadata),
            fungible_asset::project_uri(metadata)
        )
    }

    #[view]
    public fun is_dynexus_minter(minter: address): bool acquires TokenRegistry {
        borrow_global<TokenRegistry>(get_token_factory_object_addr()).minters.contains(&minter)
    }

    //
    // Test functions
    //

    #[test_only]
    public fun initalize_token_factory_with_out_genesis(admin: &signer) {
        init_module(admin)
    }

    #[test_only]
    public fun create_test_token(
        creator: &signer,
        name: String,
        symbol: String,
        decimals: u8,
        inital_supply: u64,
        icon_uri: String,
        project_uri: String,
        _index: u64
    ): (String, String, address) acquires TokenRegistry {
        create_token(
            creator,
            name,
            symbol,
            decimals,
            inital_supply,
            icon_uri,
            project_uri
        );

        let seed = create_token_seed(&name, &symbol);
        (name, symbol, object::create_object_address(&address_of(creator), seed))
    }
}
