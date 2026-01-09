// ** Importing modules from nf-neuro ** //
include { DENOISING_NLMEANS } from '../../../modules/nf-neuro/denoising/nlmeans/main'
include { PREPROC_N4 } from '../../../modules/nf-neuro/preproc/n4/main'
include { IMAGE_RESAMPLE } from '../../../modules/nf-neuro/image/resample/main'
include { BETCROP_ANTSBET } from '../../../modules/nf-neuro/betcrop/antsbet/main'
include { BETCROP_SYNTHSTRIP} from '../../../modules/nf-neuro/betcrop/synthstrip/main'
include { IMAGE_CROPVOLUME as IMAGE_CROPVOLUME_T1 } from '../../../modules/nf-neuro/image/cropvolume/main'
include { IMAGE_CROPVOLUME as IMAGE_CROPVOLUME_MASK } from '../../../modules/nf-neuro/image/cropvolume/main'

params.preproc_t1_run_synthstrip = false

workflow PREPROC_T1 {

    take:
        ch_image            // channel: [ val(meta), image ]
        ch_template         // channel: [ val(meta), template ]         , optional
        ch_probability_map  // channel: [ val(meta), probability-map ]  , optional
        ch_template_mask    // channel: [ val(meta), mask ]             , optional
        ch_initial_affine   // channel: [ val(meta), init_affine ]      , optional
        ch_ref_mask         // channel: [ val(meta), mask ]             , optional
        ch_ref_resample     // channel: [ val(meta), ref ]              , optional
        ch_weights          // channel: [ val(meta), weights ]          , optional
    main:
        ch_versions = channel.empty()
        image_nlmeans = channel.empty()
        image_N4 = channel.empty()
        image_resample = channel.empty()
        image_bet = channel.empty()
        mask_bet = channel.empty()
        image_crop = channel.empty()
        mask_crop = channel.empty()
        bbox = channel.empty()
        ch_mask = channel.empty()

        if ( params.preproc_t1_run_denoising ) {

            ch_nlmeans = ch_image
                .join(ch_ref_mask, remainder: true)
                .map{ meta, image, mask -> [meta, image, mask ?: [], []] }

            DENOISING_NLMEANS ( ch_nlmeans )
            ch_versions = ch_versions.mix(DENOISING_NLMEANS.out.versions.first())
            image_nlmeans = DENOISING_NLMEANS.out.image
            ch_image = DENOISING_NLMEANS.out.image
        }

        if ( params.preproc_t1_run_N4 ) {
            ch_N4 = ch_image
                .map{ meta, image -> [meta, image, [], []] }
                .join(ch_ref_mask, remainder: true)
                .map{ meta, image, bval, bvec, mask -> [meta, image, bval, bvec, mask ?: []] }

            PREPROC_N4 ( ch_N4 )
            ch_versions = ch_versions.mix(PREPROC_N4.out.versions.first())
            image_N4 = PREPROC_N4.out.image
            ch_image = PREPROC_N4.out.image
        }

        if ( params.preproc_t1_run_resampling ) {
            ch_resampling = ch_image
                .join(ch_ref_resample, remainder: true)
                .map{ meta, image, ref_image -> [meta, image, ref_image ?: []] }

            IMAGE_RESAMPLE ( ch_resampling )
            ch_versions = ch_versions.mix(IMAGE_RESAMPLE.out.versions.first())
            image_resample = IMAGE_RESAMPLE.out.image
            ch_image = IMAGE_RESAMPLE.out.image
        }

        if ( params.preproc_t1_run_synthstrip ) {
            ch_bet = ch_image
                .join(ch_weights, remainder: true)
                .map{ meta, image, weights -> [meta, image, weights ?: []] }

            BETCROP_SYNTHSTRIP ( ch_bet )
            ch_versions = ch_versions.mix(BETCROP_SYNTHSTRIP.out.versions.first())

            // ** Setting BET output ** //
            image_bet = BETCROP_SYNTHSTRIP.out.bet_image
            ch_image = BETCROP_SYNTHSTRIP.out.bet_image
            mask_bet = BETCROP_SYNTHSTRIP.out.brain_mask
            ch_mask = BETCROP_SYNTHSTRIP.out.brain_mask
        }
        else if ( params.preproc_t1_run_ants_bet ) {
            // ** ANTSBET ** //
            // The template and probability maps are mandatory if running antsBET. Since the
            // error message from nextflow when they are absent is either non-informative or
            // missing, we use ifEmpty to provide a more informative one.
            ch_bet = ch_image
                .join(ch_template.ifEmpty{ error("ANTS BET needs a template") })
                .join(ch_probability_map.ifEmpty{ error("ANTS BET needs a tissue probability map") })
                .join(ch_template_mask, remainder: true)
                .map{ meta, image, template, probability_map, mask -> [meta, image, template, probability_map, mask ?: []] }
                .join(ch_initial_affine, remainder: true)
                .map{ meta, image, template, probability_map, mask, init_affine -> [meta, image, template, probability_map, mask, init_affine ?: []] }

            BETCROP_ANTSBET ( ch_bet )
            ch_versions = ch_versions.mix(BETCROP_ANTSBET.out.versions.first())

            // ** Setting BET output ** //
            image_bet = BETCROP_ANTSBET.out.t1
            ch_image = BETCROP_ANTSBET.out.t1
            mask_bet = BETCROP_ANTSBET.out.mask
            ch_mask = BETCROP_ANTSBET.out.mask
        }

        if ( params.preproc_t1_run_crop ) {
            // ** Crop image ** //
            ch_crop = ch_image
                .map{ it + [[]] }

            IMAGE_CROPVOLUME_T1 ( ch_crop )
            ch_versions = ch_versions.mix(IMAGE_CROPVOLUME_T1.out.versions.first())
            image_crop = IMAGE_CROPVOLUME_T1.out.image
            ch_image = IMAGE_CROPVOLUME_T1.out.image
            bbox = IMAGE_CROPVOLUME_T1.out.bounding_box

            // ** Crop mask ** //
            ch_crop_mask = mask_bet
                .join(IMAGE_CROPVOLUME_T1.out.bounding_box)

            IMAGE_CROPVOLUME_MASK ( ch_crop_mask )
            ch_versions = ch_versions.mix(IMAGE_CROPVOLUME_MASK.out.versions.first())
            mask_crop = IMAGE_CROPVOLUME_MASK.out.image
            ch_mask = IMAGE_CROPVOLUME_MASK.out.image
        }

    emit:
        t1_final        = ch_image          // channel: [ val(meta), t1-preprocessed ]
        mask_final      = ch_mask           // channel: [ val(meta), t1-mask ]
        image_nlmeans   = image_nlmeans     // channel: [ val(meta), t1-after-denoise ]
        image_N4        = image_N4          // channel: [ val(meta), t1-after-unbias ]
        image_resample  = image_resample    // channel: [ val(meta), t1-after-resample ]
        image_bet       = image_bet         // channel: [ val(meta), t1-after-bet ]
        mask_bet        = mask_bet          // channel: [ val(meta), intermediary-mask ]
        crop_box        = bbox              // channel: [ val(meta), bounding-box ]
        versions        = ch_versions       // channel: [ versions.yml ]
}
