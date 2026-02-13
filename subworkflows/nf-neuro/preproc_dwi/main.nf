include { DENOISING_MPPCA as DENOISE_DWI } from '../../../modules/nf-neuro/denoising/mppca/main'
include { DENOISING_MPPCA as DENOISE_REVDWI } from '../../../modules/nf-neuro/denoising/mppca/main'
include { PREPROC_GIBBS as PREPROC_GIBBS_DWI } from '../../../modules/nf-neuro/preproc/gibbs/main'
include { PREPROC_GIBBS as PREPROC_GIBBS_REVDWI } from '../../../modules/nf-neuro/preproc/gibbs/main'
include { IMAGE_POWDERAVERAGE } from '../../../modules/nf-neuro/image/powderaverage/main'
include { BETCROP_SYNTHSTRIP } from '../../../modules/nf-neuro/betcrop/synthstrip/main'
include { IMAGE_APPLYMASK as BET_DWI } from '../../../modules/nf-neuro/image/applymask/main'
include { IMAGE_CROPVOLUME as CROPDWI } from '../../../modules/nf-neuro/image/cropvolume/main'
include { IMAGE_CROPVOLUME as CROPMASK } from '../../../modules/nf-neuro/image/cropvolume/main'
include { IMAGE_CONVERT as CONVERT } from '../../../modules/nf-neuro/image/convert/main'
include { BETCROP_FSLBETCROP } from '../../../modules/nf-neuro/betcrop/fslbetcrop/main'
include { PREPROC_N4 as N4_DWI } from '../../../modules/nf-neuro/preproc/n4/main'
include { PREPROC_NORMALIZE as NORMALIZE_DWI } from '../../../modules/nf-neuro/preproc/normalize/main'
include { IMAGE_RESAMPLE as RESAMPLE_DWI } from '../../../modules/nf-neuro/image/resample/main'
include { IMAGE_RESAMPLE as RESAMPLE_MASK } from '../../../modules/nf-neuro/image/resample/main'
include { UTILS_EXTRACTB0 } from '../../../modules/nf-neuro/utils/extractb0/main'
include { TOPUP_EDDY } from '../topup_eddy/main'
include { getOptionsWithDefaults } from '../utils_options/main'


workflow PREPROC_DWI {

    take:
        ch_dwi                  // channel: [ val(meta), dwi, bval, bvec ]
        ch_rev_dwi              // channel: [ val(meta), rev-dwi, bval, bvec ], optional
        ch_b0                   // channel : [ val(meta), b0 ], optional
        ch_rev_b0               // channel: [ val(meta), rev-b0 ], optional
        ch_synthstrip_weights   // channel: [ val(meta), 'weights.pt' ] or [ 'weights.pt' ], optional
        ch_config_topup         // channel: [ 'topup.cnf' ], optional
        options                 // [ optional ] map of options

    main:

        // Check to ensure options is a Map
        assert options instanceof Map : "Options must be a Map, got ${options.getClass().getName()}"

        // Merge options with defaults from meta.yml
        options = getOptionsWithDefaults(options, "${moduleDir}/meta.yml")

        ch_versions = channel.empty()
        ch_multiqc_files = channel.empty()

        // ** Denoise DWI ** //
        if ( options.preproc_dwi_run_denoising ) {
            ch_dwi_bvalbvec = ch_dwi
                .multiMap { meta, dwi, bval, bvec ->
                    dwi:    [ meta, dwi ]
                    bvs_files: [ meta, bval, bvec ]
                }

            // Need to append "rev" to the ID, to ensure output filenames
            // are different from the DWI and prevent file collisions
            //  - "cache: meta" is used to save the "real" metadata with valid ID for
            //           join operations, so it can be recovered after execution
            ch_rev_dwi_bvalbvec = ch_rev_dwi
                .multiMap { meta, dwi, bval, bvec ->
                    rev_dwi:    [ [id: "${meta.id}_rev", cache: meta], dwi ]
                    rev_bvs_files: [ meta, bval, bvec ]
                }

            ch_denoise_dwi = ch_dwi_bvalbvec.dwi
                .map{ meta, dwi -> [ meta, dwi, []] }

            DENOISE_DWI ( ch_denoise_dwi )
            ch_versions = ch_versions.mix(DENOISE_DWI.out.versions.first())

            // ** Denoise REV-DWI ** //
            ch_denoise_rev_dwi = ch_rev_dwi_bvalbvec.rev_dwi
                .map{ meta, dwi -> [ meta, dwi, []] }

            DENOISE_REVDWI ( ch_denoise_rev_dwi )
            ch_versions = ch_versions.mix(DENOISE_REVDWI.out.versions.first())

            ch_dwi = DENOISE_DWI.out.image
                .join(ch_dwi_bvalbvec.bvs_files)
            // Recover the "real" ID from "meta[cache]" (see above), to join with the bval/bvec
            ch_rev_dwi = DENOISE_REVDWI.out.image
                .map{ meta, dwi -> [ meta.cache, dwi ] }
                .join(ch_rev_dwi_bvalbvec.rev_bvs_files)
        } // No else, we just use ch_dwi

        if ( options.preproc_dwi_run_degibbs ) {
            ch_dwi_bvalbvec = ch_dwi
                .multiMap { meta, dwi, bval, bvec ->
                    dwi:    [ meta, dwi ]
                    bvs_files: [ meta, bval, bvec ]
                }

            ch_rev_dwi_bvalbvec = ch_rev_dwi
                .multiMap { meta, dwi, bval, bvec ->
                    rev_dwi:    [ [id: "${meta.id}_rev", cache: meta], dwi ]
                    rev_bvs_files: [ meta, bval, bvec ]
                }

            PREPROC_GIBBS_DWI(ch_dwi_bvalbvec.dwi)
            ch_versions = ch_versions.mix(PREPROC_GIBBS_DWI.out.versions.first())

            // Need to append "rev" to the ID, to ensure output filenames
            // are different from the DWI and prevent file collisions
            //  - "cache: meta" is used to save the "real" metadata with valid ID for
            //           join operations, so it can be recovered after execution
            PREPROC_GIBBS_REVDWI(ch_rev_dwi_bvalbvec.rev_dwi)
            ch_versions = ch_versions.mix(PREPROC_GIBBS_REVDWI.out.versions.first())

            ch_dwi = PREPROC_GIBBS_DWI.out.dwi
                .join(ch_dwi_bvalbvec.bvs_files)
            // Recover the "real" ID from "meta[cache]" (see above), to join with the bval/bvec
            ch_rev_dwi = PREPROC_GIBBS_REVDWI.out.dwi
                .map{ meta, dwi -> [ meta.cache, dwi ] }
                .join(ch_rev_dwi_bvalbvec.rev_bvs_files)
        } // No else, we just use ch_dwi

        // ** Eddy Topup ** //
        if ( options.topup_eddy_run_topup || options.topup_eddy_run_eddy ) {
            TOPUP_EDDY (
                ch_dwi,
                ch_b0,
                ch_rev_dwi,
                ch_rev_b0,
                ch_config_topup.ifEmpty( "b02b0.cnf" ),
                [
                    "topup_eddy_run_topup": options.topup_eddy_run_topup,
                    "topup_eddy_run_eddy": options.topup_eddy_run_eddy
                ] )
            ch_versions = ch_versions.mix(TOPUP_EDDY.out.versions.first())
            ch_multiqc_files = ch_multiqc_files.mix(TOPUP_EDDY.out.mqc)

            ch_dwi = TOPUP_EDDY.out.dwi
                        .join(TOPUP_EDDY.out.bval)
                        .join(TOPUP_EDDY.out.bvec)
        }
        // ** Bet-crop DWI ** //
        if ( options.preproc_dwi_run_synthstrip ) {

            ch_pwd_avg = ch_dwi
                .map{ meta, dwi, bval, _bvec -> [ meta, dwi, bval, [] ] }

            ch_bvals_bvecs = ch_dwi
                .map{ meta, _dwi, bval, bvec -> [ meta, bval, bvec ] }

            IMAGE_POWDERAVERAGE ( ch_pwd_avg )
            ch_versions = ch_versions.mix(IMAGE_POWDERAVERAGE.out.versions.first())
            ch_pwd_avg = IMAGE_POWDERAVERAGE.out.pwd_avg

            // Assess if weights were provided per meta or not
            ch_weights = ch_synthstrip_weights.ifEmpty( [] )
                .branch { it ->
                    subject: (it instanceof List && it.size() == 2)
                        return it
                    single: it instanceof List || it instanceof String
                        return it
                }

            ch_synthstrip_single = IMAGE_POWDERAVERAGE.out.pwd_avg
                .combine(ch_weights.single)
                .map{ tuple ->
                    def meta = tuple[0]
                    def pwd_avg = tuple[1]
                    def weights = tuple.size() > 2 ? tuple[2] : []
                    return [ meta, pwd_avg, weights ]
                }
            ch_synthstrip_subject = IMAGE_POWDERAVERAGE.out.pwd_avg
                .join(ch_weights.subject, remainder: true)
                .map{ meta, pwd_avg, weights ->
                    [ meta, pwd_avg, weights ?: [] ]
                }
            ch_synthstrip = ch_synthstrip_single
                .mix( ch_synthstrip_subject )
                .unique()
            BETCROP_SYNTHSTRIP ( ch_synthstrip )
            ch_versions = ch_versions.mix(BETCROP_SYNTHSTRIP.out.versions.first())

            // Use the SynthStrip mask to BET the DWI
            ch_apply_mask = ch_dwi
                .join(BETCROP_SYNTHSTRIP.out.brain_mask)
                .map{ meta, dwi, _bval, _bvec, mask -> [ meta, dwi, mask ] }

            BET_DWI ( ch_apply_mask )
            ch_versions = ch_versions.mix(BET_DWI.out.versions.first())

            // Crop the DWI since it is not done in BET_DWI
            CROPDWI ( BET_DWI.out.image.map { meta, img -> [ meta, img, [] ] } )
            ch_versions = ch_versions.mix(CROPDWI.out.versions.first())

            ch_cropmask = BETCROP_SYNTHSTRIP.out.brain_mask
                .join(CROPDWI.out.bounding_box)

            CROPMASK ( ch_cropmask )
            ch_versions = ch_versions.mix(CROPMASK.out.versions.first())

            // Convert cropped mask to uint8
            CONVERT ( CROPMASK.out.image )
            ch_versions = ch_versions.mix(CONVERT.out.versions.first())

            if ( !options.preproc_dwi_keep_dwi_with_skull) {
                ch_dwi = CROPDWI.out.image
                            .join(ch_bvals_bvecs)
            }
            ch_mask = CONVERT.out.image
            ch_bbox = CROPDWI.out.bounding_box

        } else {
            // ** Bet-crop DWI with FSL BETCROP ** //
            ch_pwd_avg = channel.empty()
            ch_bvals_bvecs = ch_dwi
                .map{ meta, _dwi, bval, bvec -> [ meta, bval, bvec ] }

            BETCROP_FSLBETCROP ( ch_dwi )
            ch_versions = ch_versions.mix(BETCROP_FSLBETCROP.out.versions.first())

            if ( !options.preproc_dwi_keep_dwi_with_skull) {
                ch_dwi = BETCROP_FSLBETCROP.out.image
                            .join(ch_bvals_bvecs)
            }
            ch_mask = BETCROP_FSLBETCROP.out.mask
            ch_bbox = BETCROP_FSLBETCROP.out.bbox
        } // No else, we just use ch_dwi

        if ( options.preproc_dwi_run_N4 ) {
            // ** N4 DWI ** //
            ch_N4 = ch_dwi
                .join(ch_mask, remainder: true)

            ch_bvals_bvecs = ch_dwi
                .map{ meta, _dwi, bval, bvec -> [ meta, bval, bvec ] }

            N4_DWI ( ch_N4 )
            ch_versions = ch_versions.mix(N4_DWI.out.versions.first())

            ch_dwi = N4_DWI.out.image
                        .join(ch_bvals_bvecs)
        } // No else, we just use ch_dwi

        if ( options.preproc_dwi_run_normalize ) {
            // ** Normalize DWI ** //
            ch_normalize = ch_dwi
                .join(ch_mask)

            ch_bvals_bvecs = ch_dwi
                .map{ meta, _dwi, bval, bvec -> [ meta, bval, bvec ] }

            NORMALIZE_DWI ( ch_normalize )
            ch_versions = ch_versions.mix(NORMALIZE_DWI.out.versions.first())

            ch_dwi = NORMALIZE_DWI.out.dwi
                        .join(ch_bvals_bvecs)
        } // No else, we just use ch_dwi

        if ( options.preproc_dwi_run_resampling ) {
            // ** Resample DWI ** //
            ch_resample_dwi = ch_dwi
                .map{ meta, dwi, _bval, _bvec -> [ meta, dwi, [] ] }

            ch_bvals_bvecs = ch_dwi
                .map{ meta, _dwi, bval, bvec -> [ meta, bval, bvec ] }

            RESAMPLE_DWI ( ch_resample_dwi )
            ch_versions = ch_versions.mix(RESAMPLE_DWI.out.versions.first())

            ch_dwi = RESAMPLE_DWI.out.image
                        .join(ch_bvals_bvecs)
        } // No else, we just use ch_dwi

        // ** Extract B0 ** //
        UTILS_EXTRACTB0 ( ch_dwi )
        ch_versions = ch_versions.mix(UTILS_EXTRACTB0.out.versions.first())

        if ( options.preproc_dwi_run_resampling ) {
            // ** Resample mask ** //
            ch_resample_mask = ch_mask
                .join(UTILS_EXTRACTB0.out.b0)

            RESAMPLE_MASK ( ch_resample_mask )
            ch_mask = RESAMPLE_MASK.out.image
            ch_versions = ch_versions.mix(RESAMPLE_MASK.out.versions.first())
        }

        ch_dwi_preproc = ch_dwi
            .map{ meta, dwi, _bval, _bvec -> [ meta, dwi ] }

        ch_bval = ch_dwi
            .map{ meta, _dwi, bval, _bvec -> [ meta, bval ] }

        ch_bvec = ch_dwi
            .map{ meta, _dwi, _bval, bvec -> [ meta, bvec ] }

    emit:
        dwi                 = ch_dwi_preproc                        // channel: [ val(meta), dwi-preproc ]
        bval                = ch_bval           // channel: [ val(meta), bval-corrected ]
        bvec                = ch_bvec           // channel: [ val(meta), bvec-corrected ]
        pwd_avg             = ch_pwd_avg                    // channel: [ val(meta), pwd-avg ]
        b0                  = UTILS_EXTRACTB0.out.b0        // channel: [ val(meta), b0-preproc ]
        b0_mask             = ch_mask                       // channel: [ val(meta), b0-mask ]
        dwi_bounding_box    = ch_bbox                       // channel: [ val(meta), dwi-bounding-box ]
        mqc                 = ch_multiqc_files              // channel: [ val(meta), mqc ]
        versions            = ch_versions                   // channel: [ versions.yml ]
}
